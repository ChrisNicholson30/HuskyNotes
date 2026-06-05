//
//  PrintService.swift
//  HuskyNotes
//
//  Opens the system print dialog for a single note, rendered as Read mode.
//
//  • iOS/iPadOS: prints the paginated PDF from `PDFRenderer` via
//    `UIPrintInteractionController` (anchored for the iPad popover).
//  • macOS: prints that same PDF through `NSPrintOperation`, drawing each PDF
//    page in a small `NSView`. (Printing a detached `NSHostingView` renders
//    blank — the SwiftUI content isn't drawn during the print pass — so we print
//    the already-rendered PDF instead.)
//

import SwiftUI

#if os(iOS)
import UIKit

/// Presents the iOS/iPadOS print dialog for a note.
@MainActor
enum PrintService {
    static func print(note: Note, theme: Theme) {
        guard let data = PDFRenderer.pdfData(for: note, theme: theme) else { return }

        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = note.title.isEmpty ? "Husky Note" : note.title

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data

        // iPad requires an anchor for the print popover; iPhone presents modally.
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = scene.keyWindow ?? scene.windows.first {
            let anchor = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            controller.present(from: anchor, in: window, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }
}

#elseif os(macOS)
import AppKit
import PDFKit

/// Presents the macOS print panel for a note.
@MainActor
enum PrintService {
    static func print(note: Note, theme: Theme) {
        guard let data = PDFRenderer.pdfData(for: note, theme: theme),
              let document = PDFDocument(data: data), document.pageCount > 0 else { return }

        // The PDF already bakes in the page size and margins, so print it 1:1.
        let pageSize = document.page(at: 0)?.bounds(for: .mediaBox).size ?? NSSize(width: 612, height: 792)

        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .clip
        printInfo.verticalPagination = .clip
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let view = PDFPrintView(document: document, pageSize: pageSize)
        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.jobTitle = note.title.isEmpty ? "Husky Note" : note.title
        operation.run()
    }
}

/// An off-screen view that lays a PDF out one page per printed page and draws each
/// page's content directly — reliable where printing a live `NSHostingView`
/// renders blank.
private final class PDFPrintView: NSView {
    private let document: PDFDocument
    private let pageSize: NSSize

    init(document: PDFDocument, pageSize: NSSize) {
        self.document = document
        self.pageSize = pageSize
        let height = pageSize.height * CGFloat(max(1, document.pageCount))
        super.init(frame: NSRect(x: 0, y: 0, width: pageSize.width, height: height))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// One printed page per PDF page.
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(1, document.pageCount))
        return true
    }

    /// Pages are stacked top-to-bottom in this bottom-left-origin view, so page 1
    /// is the highest slice.
    override func rectForPage(_ page: Int) -> NSRect {
        let y = bounds.height - CGFloat(page) * pageSize.height
        return NSRect(x: 0, y: y, width: pageSize.width, height: pageSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let y = bounds.height - CGFloat(index + 1) * pageSize.height
            let slot = NSRect(x: 0, y: y, width: pageSize.width, height: pageSize.height)
            guard slot.intersects(dirtyRect) else { continue }

            ctx.saveGState()
            ctx.translateBy(x: slot.minX, y: slot.minY)
            // Scale the page's media box into the slot (1:1 for our US-Letter PDF).
            let media = page.bounds(for: .mediaBox)
            if media.width > 0, media.height > 0 {
                ctx.scaleBy(x: pageSize.width / media.width, y: pageSize.height / media.height)
                ctx.translateBy(x: -media.minX, y: -media.minY)
            }
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
        }
    }
}
#endif
