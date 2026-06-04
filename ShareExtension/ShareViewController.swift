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
        capture()
    }

    /// Pulls URL / text / JS-preprocessed page info from the extension context.
    private func capture() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments
        else { return finish() }

        var urlString: String?
        var text: String?
        var jsTitle: String?
        let fallbackTitle = item.attributedContentText?.string ?? ""

        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { value, _ in
                    if let dict = value as? [String: Any],
                       let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                        jsTitle = results["title"] as? String
                        if urlString == nil { urlString = results["url"] as? String }
                        if text == nil { text = results["selection"] as? String }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                    if let url = value as? URL { urlString = url.absoluteString }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
                    if let string = value as? String { text = string }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let title = (jsTitle?.isEmpty == false ? jsTitle : nil)
                ?? (fallbackTitle.isEmpty ? (urlString ?? "Shared Page") : fallbackTitle)
            SharedInbox.append(
                SharedInbox.Item(title: title ?? "Shared Page", urlString: urlString, text: text)
            )
            self?.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
