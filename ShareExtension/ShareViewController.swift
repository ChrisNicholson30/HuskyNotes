//
//  ShareViewController.swift
//  HuskyNotes-ShareExtension
//
//  The Share Extension shown in Safari (and other browsers/apps) on iOS/iPadOS.
//  It captures the shared page — URL, title, and any selected text (via a small
//  JavaScript preprocessing file) — writes it to the App Group inbox, and
//  finishes. The main app turns inbox items into notes on next launch.
//

import UIKit
import UniformTypeIdentifiers

/// Captures shared web content into the App Group inbox.
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

    /// Pulls URL / text / JS-preprocessed page info from the extension context.
    /// Loads run sequentially via `await`, so there are no concurrent captures.
    private func capture() async {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments
        else { return finish() }

        let fallbackTitle = item.attributedContentText?.string ?? ""
        var urlString: String?
        var text: String?
        var jsTitle: String?

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                if let results = await loadJSResults(provider) {
                    if let title = results["title"] { jsTitle = title }
                    if urlString == nil { urlString = results["url"] }
                    if text == nil { text = results["selection"] }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let loaded = await loadURLString(provider) { urlString = loaded }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let loaded = await loadString(provider, UTType.plainText.identifier) { text = loaded }
            }
        }

        let title: String
        if let jsTitle, !jsTitle.isEmpty {
            title = jsTitle
        } else if !fallbackTitle.isEmpty {
            title = fallbackTitle
        } else {
            title = urlString ?? "Shared Page"
        }

        SharedInbox.append(SharedInbox.Item(title: title, urlString: urlString, text: text))
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

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
