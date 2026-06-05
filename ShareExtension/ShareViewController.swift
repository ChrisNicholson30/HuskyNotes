//
//  ShareViewController.swift
//  HuskyNotes-ShareExtension
//
//  The Share Extension shown from Safari, Photos, Files and other apps. It
//  captures whatever was shared — a web page (URL + title + selection via a JS
//  preprocessing file), plain text, images, PDFs, or arbitrary files — writes a
//  single self-contained item to the App Group inbox, and finishes. The main app
//  turns inbox items into notes (with attachments) on next launch/foreground.
//

import UIKit
import UniformTypeIdentifiers

/// Captures shared content into the App Group inbox.
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await capture() }
    }

    /// Walks every input item and attachment provider, capturing text/URL and
    /// any image/PDF/file attachments into a single inbox item.
    private func capture() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

        var urlString: String?
        var text: String?
        var jsTitle: String?
        var fallbackTitle = ""
        var attachments: [SharedInbox.Attachment] = []

        for item in items {
            if fallbackTitle.isEmpty, let content = item.attributedContentText?.string, !content.isEmpty {
                fallbackTitle = content
            }
            for provider in item.attachments ?? [] {
                // Web page (JS results) takes priority — it carries url/title/selection.
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    if let results = await loadJSResults(provider) {
                        if let title = results["title"], !title.isEmpty { jsTitle = title }
                        if urlString == nil { urlString = results["url"] }
                        if text == nil, let selection = results["selection"], !selection.isEmpty { text = selection }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let attachment = await storeFile(provider, conformingTo: .image, isImage: true) {
                        attachments.append(attachment)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    if let attachment = await storeFile(provider, conformingTo: .pdf, isImage: false) {
                        attachments.append(attachment)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let loaded = await loadURLString(provider) { urlString = loaded }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let loaded = await loadString(provider, UTType.plainText.identifier), !loaded.isEmpty {
                        text = loaded
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                    // Generic file fallback (documents, archives, etc.).
                    if let attachment = await storeFile(provider, conformingTo: .item, isImage: false) {
                        attachments.append(attachment)
                    }
                }
            }
        }

        let title = [jsTitle, fallbackTitle, attachments.first?.filename, urlString]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty }) ?? "Shared"

        // Only enqueue if we actually captured something useful.
        if urlString != nil || text != nil || !attachments.isEmpty {
            SharedInbox.append(SharedInbox.Item(
                title: title,
                urlString: urlString,
                text: text,
                attachments: attachments
            ))
        }
        finish()
    }

    // MARK: Typed loaders (return only Sendable values, so nothing races)

    private func loadString(_ provider: NSItemProvider, _ typeID: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }

    private func loadURLString(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                continuation.resume(returning: (value as? URL)?.absoluteString)
            }
        }
    }

    private func loadJSResults(_ provider: NSItemProvider) async -> [String: String]? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { value, _ in
                let dict = value as? [String: Any]
                let results = dict?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
                var output: [String: String] = [:]
                if let title = results?["title"] as? String { output["title"] = title }
                if let url = results?["url"] as? String { output["url"] = url }
                if let selection = results?["selection"] as? String { output["selection"] = selection }
                continuation.resume(returning: output.isEmpty ? nil : output)
            }
        }
    }

    /// Copies the provider's file representation into the inbox (memory-safe for
    /// large files — never loads the whole blob into memory).
    private func storeFile(_ provider: NSItemProvider, conformingTo type: UTType, isImage: Bool) async -> SharedInbox.Attachment? {
        // Prefer the most specific concrete type the provider offers.
        let typeID = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: type) ?? false
        } ?? type.identifier

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                // The temp URL is valid only inside this completion — copy now.
                let resolvedType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? typeID
                let attachment = SharedInbox.storeAttachment(
                    at: url,
                    filename: url.lastPathComponent,
                    contentType: resolvedType,
                    isImage: isImage
                )
                continuation.resume(returning: attachment)
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
