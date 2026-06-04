//
//  MarkdownEditor.swift
//  HuskyNotes
//
//  A SwiftUI bridge over a TextKit 2 backed platform text view (UITextView on
//  iOS/iPadOS, NSTextView on macOS) that provides *live source styling* of
//  Markdown. The user edits the canonical CommonMark/GFM source directly; on
//  every change the text is re-styled via `MarkdownStyler` so headings, emphasis,
//  code, quotes and links are decorated while their syntax characters stay
//  visible.
//
//  Theming is decoupled from storage: every colour (background, text, insertion
//  point, selection) is read from the supplied `Theme`. Nothing is hard-coded.
//
//  TextKit 2 stack:
//    • iOS/iPadOS 16+: `UITextView` is TextKit 2 backed by default.
//    • macOS: created with `NSTextView(usingTextLayoutManager: true)`.
//
//  The view binds `text` two ways: external changes flow in via `updateUIView`/
//  `updateNSView`; user edits flow out from the Coordinator's text-did-change
//  callback. Re-styling preserves the user's selection so the caret never jumps.
//

import SwiftUI

// MARK: - MarkdownEditor

#if os(iOS)

/// SwiftUI wrapper around a TextKit 2 `UITextView` providing live Markdown
/// source styling for iOS and iPadOS.
struct MarkdownEditor: UIViewRepresentable {

    /// The canonical Markdown source. Mutated as the user types.
    @Binding var text: String

    /// The active theme supplying every colour, font and metric.
    let theme: Theme

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, theme: theme)
    }

    func makeUIView(context: Context) -> UITextView {
        // UITextView is TextKit 2 backed by default on iOS 16+. Constructing it
        // with the default initialiser keeps us on the TextKit 2 stack.
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = theme.background.platformColor
        textView.tintColor = theme.accent.platformColor
        textView.alwaysBounceVertical = true
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .no      // preserve literal "--" in Markdown
        textView.smartQuotesType = .no       // preserve straight quotes for code
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.keyboardDismissMode = .interactive

        context.coordinator.textView = textView
        // Open with the caret at the end so a freshly created "# " note is ready
        // to type the title into.
        let caret = NSRange(location: (text as NSString).length, length: 0)
        context.coordinator.apply(source: text, to: textView, selection: caret)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Keep the coordinator's theme current so callbacks re-style correctly.
        context.coordinator.theme = theme

        // Honour theme changes that don't originate from a text edit.
        textView.backgroundColor = theme.background.platformColor
        textView.tintColor = theme.accent.platformColor

        // Only rewrite storage when the external binding diverges from the
        // view's text (e.g. a different note loaded) or the theme changed —
        // never on every keystroke, which would fight the user's typing.
        if textView.text != text || context.coordinator.styledTheme != theme {
            context.coordinator.apply(source: text, to: textView)
        }
    }
}

#elseif os(macOS)

/// SwiftUI wrapper around a TextKit 2 `NSTextView` (inside an `NSScrollView`)
/// providing live Markdown source styling for macOS.
struct MarkdownEditor: NSViewRepresentable {

    /// The canonical Markdown source. Mutated as the user types.
    @Binding var text: String

    /// The active theme supplying every colour, font and metric.
    let theme: Theme

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, theme: theme)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Force the TextKit 2 stack explicitly on macOS.
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false            // we own all styling
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.backgroundColor = theme.background.platformColor
        textView.insertionPointColor = theme.accent.platformColor
        textView.selectedTextAttributes = [
            .backgroundColor: theme.selection.platformColor
        ]
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background.platformColor

        context.coordinator.textView = textView
        // Open with the caret at the end so a freshly created "# " note is ready
        // to type the title into.
        let caret = NSRange(location: (text as NSString).length, length: 0)
        context.coordinator.apply(source: text, to: textView, selection: caret)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.theme = theme

        textView.backgroundColor = theme.background.platformColor
        scrollView.backgroundColor = theme.background.platformColor
        textView.insertionPointColor = theme.accent.platformColor
        textView.selectedTextAttributes = [
            .backgroundColor: theme.selection.platformColor
        ]

        if textView.string != text || context.coordinator.styledTheme != theme {
            context.coordinator.apply(source: text, to: textView)
        }
    }
}

#endif

// MARK: - Coordinator

extension MarkdownEditor {

    /// Bridges the platform text view's editing callbacks back to SwiftUI and
    /// owns the (re-)styling of the text storage. Shared between the iOS and
    /// macOS representables — only the delegate conformance differs.
    final class Coordinator: NSObject {

        /// Two-way binding to the canonical Markdown source.
        private let text: Binding<String>

        /// The active theme; updated by `updateUIView`/`updateNSView`.
        var theme: Theme

        /// The theme last used to style the storage, so we can detect when a
        /// theme switch requires a full re-style even if the text is unchanged.
        private(set) var styledTheme: Theme?

        /// The text view this coordinator drives; used to apply menu commands and
        /// to restyle on selection changes. Weak to avoid a retain cycle.
        weak var textView: PlatformTextView?

        /// Guards against re-entrant restyling: programmatically setting the
        /// selection during `apply` itself fires selection-change callbacks.
        private var isApplying = false

        /// The styler that turns Markdown source into a themed attributed string.
        private let styler = MarkdownStyler()

        init(text: Binding<String>, theme: Theme) {
            self.text = text
            self.theme = theme
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFormatCommand(_:)),
                name: .huskyFormatCommand,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Re-styles `source` into the text view, revealing the syntax markers on
        /// the line that contains `selection` (defaulting to the view's current
        /// selection) and restoring that selection afterwards.
        ///
        /// This is the single funnel for mutating the displayed attributed text:
        /// initial load, post-edit restyle, caret-move reveal, and menu commands
        /// all route through it.
        func apply(source: String, to textView: PlatformTextView, selection: NSRange? = nil) {
            isApplying = true
            defer { isApplying = false }

            let length = (source as NSString).length
            let desired = clampedSelection(selection ?? currentSelection(of: textView), length: length)
            let revealed = revealedRange(in: source, for: desired)
            let styled = styler.attributedString(for: source, theme: theme, revealing: revealed)

            #if os(iOS)
            let storage = textView.textStorage
            storage.beginEditing()
            storage.setAttributedString(styled)
            storage.endEditing()
            textView.selectedRange = clampedSelection(desired, length: styled.length)
            #elseif os(macOS)
            guard let storage = textView.textStorage else { return }
            storage.beginEditing()
            storage.setAttributedString(styled)
            storage.endEditing()
            textView.setSelectedRange(clampedSelection(desired, length: styled.length))
            #endif

            styledTheme = theme
        }

        /// Pulls the current text out of the view, publishes it to the binding,
        /// then re-styles in place. Called from the text-did-change delegate.
        fileprivate func handleTextChanged(_ textView: PlatformTextView) {
            let current = currentText(of: textView)
            if text.wrappedValue != current {
                text.wrappedValue = current
            }
            // Don't restyle mid-composition (IME marked text) — it would tear
            // down the in-progress glyphs. The final commit restyles.
            guard !hasMarkedText(textView) else { return }
            apply(source: current, to: textView)
        }

        /// Re-conceals/reveals markers when the caret moves to a different line.
        fileprivate func handleSelectionChanged(_ textView: PlatformTextView) {
            guard !isApplying, !hasMarkedText(textView) else { return }
            apply(source: currentText(of: textView), to: textView)
        }

        /// Applies a formatting command broadcast from the `Format` menu — but
        /// only to the editor that is currently first responder.
        @objc private func handleFormatCommand(_ notification: Notification) {
            guard
                let textView,
                isFirstResponder(textView),
                let command = MarkdownCommand.from(notification)
            else { return }

            let result = MarkdownFormatting.apply(
                command,
                to: currentText(of: textView),
                selection: currentSelection(of: textView)
            )
            text.wrappedValue = result.text
            apply(source: result.text, to: textView, selection: result.selection)
        }

        // MARK: Platform accessors

        private func currentText(of textView: PlatformTextView) -> String {
            #if os(iOS)
            return textView.text ?? ""
            #else
            return textView.string
            #endif
        }

        private func currentSelection(of textView: PlatformTextView) -> NSRange {
            #if os(iOS)
            return textView.selectedRange
            #else
            return textView.selectedRange()
            #endif
        }

        private func isFirstResponder(_ textView: PlatformTextView) -> Bool {
            #if os(iOS)
            return textView.isFirstResponder
            #else
            return textView.window?.firstResponder === textView
            #endif
        }

        private func hasMarkedText(_ textView: PlatformTextView) -> Bool {
            #if os(iOS)
            return textView.markedTextRange != nil
            #else
            return textView.hasMarkedText()
            #endif
        }

        /// The paragraph range containing `selection`; its markers stay revealed.
        private func revealedRange(in source: String, for selection: NSRange) -> NSRange? {
            let ns = source as NSString
            guard ns.length > 0 else { return nil }
            return ns.paragraphRange(for: clampedSelection(selection, length: ns.length))
        }

        /// Clamps a selection range to the bounds of a string of `length`.
        private func clampedSelection(_ range: NSRange, length: Int) -> NSRange {
            let location = min(max(range.location, 0), length)
            let maxLen = length - location
            let len = min(max(range.length, 0), maxLen)
            return NSRange(location: location, length: len)
        }
    }
}

// MARK: - Delegate conformances

#if os(iOS)
extension MarkdownEditor.Coordinator: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        handleTextChanged(textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        handleSelectionChanged(textView)
    }
}
#elseif os(macOS)
extension MarkdownEditor.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        handleTextChanged(textView)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        handleSelectionChanged(textView)
    }
}
#endif
