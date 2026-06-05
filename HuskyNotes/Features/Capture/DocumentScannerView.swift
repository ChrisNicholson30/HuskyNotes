//
//  DocumentScannerView.swift
//  HuskyNotes
//
//  iOS/iPadOS document scanner: VisionKit's `VNDocumentCameraViewController` does
//  edge detection, deskew and multi-page capture for free. The scanned pages are
//  assembled into a single PDF (returned as `Data`) which the editor imports as a
//  normal attachment — and then OCRs (see `AttachmentOCR`). macOS has no camera
//  scanner API, so this is iOS-only.
//

#if os(iOS)
import SwiftUI
import VisionKit
import UIKit

/// Presents the system document camera and returns the captured pages as a single
/// PDF (`Data`), or `nil` if the user cancels or capture fails.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onComplete: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    // `@MainActor` + `@preconcurrency` conformance: VisionKit calls the delegate
    // on the main thread, so isolating the coordinator to the main actor lets us
    // touch `controller`/`onComplete`/`scan` without Swift 6 data-race errors.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        private let onComplete: (Data?) -> Void
        init(onComplete: @escaping (Data?) -> Void) { self.onComplete = onComplete }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let pdf = Self.pdfData(from: scan)
            controller.dismiss(animated: true) { self.onComplete(pdf) }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { self.onComplete(nil) }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            controller.dismiss(animated: true) { self.onComplete(nil) }
        }

        /// Combines the scanned page images into one PDF (each page sized to its image).
        private static func pdfData(from scan: VNDocumentCameraScan) -> Data? {
            guard scan.pageCount > 0 else { return nil }
            let firstBounds = CGRect(origin: .zero, size: scan.imageOfPage(at: 0).size)
            let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)
            return renderer.pdfData { ctx in
                for index in 0..<scan.pageCount {
                    let image = scan.imageOfPage(at: index)
                    let bounds = CGRect(origin: .zero, size: image.size)
                    ctx.beginPage(withBounds: bounds, pageInfo: [:])
                    image.draw(in: bounds)
                }
            }
        }
    }
}
#endif
