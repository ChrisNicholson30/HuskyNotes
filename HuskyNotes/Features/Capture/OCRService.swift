//
//  OCRService.swift
//  HuskyNotes
//
//  On-device text recognition (OCR) for attachments, via Apple's Vision
//  framework — private, offline, free. Recognized text is a **derived cache**
//  (the "derived store" pattern): it's computed from the attachment bytes, never
//  part of the canonical Markdown, and used to make scanned/handwritten/photo
//  text searchable. Works on iOS and macOS (Vision is cross-platform); only the
//  document *scanner* (DocumentScannerView) is iOS-only.
//

import Foundation
import Vision
import PDFKit
import ImageIO
import UniformTypeIdentifiers

/// Pure, platform-agnostic OCR: bytes in, recognized text out. Has no UI and no
/// model/main-actor state, so it's safe to call from a background task.
enum OCRService {

    /// Whether OCR is worth attempting for this attachment (image or PDF).
    static func canRecognize(contentType: String?, data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        if isPDF(contentType, data: data) { return true }
        if let ct = contentType, let type = UTType(ct) { return type.conforms(to: .image) }
        return false
    }

    /// Recognized text for an attachment's bytes, or `nil` if there's none / it
    /// isn't a supported type. Synchronous and CPU-bound — call off the main actor.
    static func recognizeText(in data: Data, contentType: String?) -> String? {
        if isPDF(contentType, data: data) { return textFromPDF(data) }
        if let cgImage = cgImage(from: data) { return recognize(cgImage) }
        return nil
    }

    // MARK: - Images

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Runs Vision text recognition on a single image.
    private static func recognize(_ cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    // MARK: - PDFs

    private static func isPDF(_ contentType: String?, data: Data) -> Bool {
        if contentType == UTType.pdf.identifier { return true }
        return data.prefix(4).elementsEqual([0x25, 0x50, 0x44, 0x46]) // "%PDF"
    }

    /// Text for a PDF: prefer its embedded text layer (exact + instant); fall back
    /// to OCR'ing each rasterized page (capped) for scanned/image-only PDFs.
    private static func textFromPDF(_ data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }

        if let embedded = document.string?.trimmingCharacters(in: .whitespacesAndNewlines), !embedded.isEmpty {
            return embedded
        }

        var pieces: [String] = []
        let maxPages = min(document.pageCount, 30)
        for index in 0..<maxPages {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pixelSize = CGSize(width: bounds.width * 2, height: bounds.height * 2) // ~144 dpi
            guard let cgImage = rasterize(page, bounds: bounds, pixelSize: pixelSize),
                  let text = recognize(cgImage) else { continue }
            pieces.append(text)
        }
        let text = pieces.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// Renders a PDF page to a `CGImage` for OCR.
    private static func rasterize(_ page: PDFPage, bounds: CGRect, pixelSize: CGSize) -> CGImage? {
        let width = Int(pixelSize.width), height = Int(pixelSize.height)
        guard width > 0, height > 0, bounds.width > 0, bounds.height > 0,
              let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: pixelSize.width / bounds.width, y: pixelSize.height / bounds.height)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}
