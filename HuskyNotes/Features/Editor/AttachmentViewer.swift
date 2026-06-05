//
//  AttachmentViewer.swift
//  HuskyNotes
//
//  Views an attachment in a sheet: PDFs in a PDFKit reader, everything else via
//  Quick Look. PDFs render straight from the stored bytes; other types are
//  written to a temp file (Quick Look needs a URL) and cleaned up on dismiss.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
#if os(iOS)
import QuickLook
#elseif os(macOS)
import Quartz
#endif

/// Presents a single ``Attachment`` full-screen for reading.
struct AttachmentViewer: View {

    let attachment: Attachment

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    /// Temp file URL for Quick Look (non-PDF types).
    @State private var quickLookURL: URL?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear { prepareIfNeeded() }
        .onDisappear { cleanup() }
    }

    @ViewBuilder
    private var content: some View {
        if isPDF, let data = attachment.data {
            PDFKitView(data: data)
                .background(theme.background.swiftUIColor)
        } else if let quickLookURL {
            QuickLookView(url: quickLookURL)
        } else {
            ContentUnavailableView("Can't preview", systemImage: "doc")
                .background(theme.background.swiftUIColor)
        }
    }

    /// Whether the attachment is a PDF (by UTI or extension).
    private var isPDF: Bool {
        attachment.contentType == UTType.pdf.identifier
            || attachment.filename.lowercased().hasSuffix(".pdf")
    }

    /// Writes non-PDF data to a temp file so Quick Look can read it.
    private func prepareIfNeeded() {
        guard !isPDF, let data = attachment.data else { return }
        let name = attachment.filename.isEmpty ? attachment.id.uuidString : attachment.filename
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            quickLookURL = url
        } catch {
            quickLookURL = nil
        }
    }

    private func cleanup() {
        if let quickLookURL { try? FileManager.default.removeItem(at: quickLookURL) }
    }
}

// MARK: - PDFKit

#if os(iOS)
/// A PDFKit reader rendering a PDF from raw bytes.
struct PDFKitView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document == nil { view.document = PDFDocument(data: data) }
    }
}
#elseif os(macOS)
/// A PDFKit reader rendering a PDF from raw bytes.
struct PDFKitView: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document == nil { view.document = PDFDocument(data: data) }
    }
}
#endif

// MARK: - Quick Look

#if os(iOS)
/// A Quick Look preview of a file URL (iOS).
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        controller.reloadData()
    }
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#elseif os(macOS)
/// A Quick Look preview of a file URL (macOS).
struct QuickLookView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView()
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}
#endif
