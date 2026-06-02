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

        context.coordinator.apply(source: text, to: textView)
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

        context.coordinator.apply(source: text, to: textView)
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

        /// The styler that turns Markdown source into a themed attributed string.
        private let styler = MarkdownStyler()

        init(text: Binding<String>, theme: Theme) {
            self.text = text
            self.theme = theme
        }

        /// Re-styles `source` and writes the result into the text view's storage,
        /// preserving the current selection so the caret does not jump.
        ///
        /// This is the single funnel for mutating the displayed attributed text;
        /// both initial load and post-edit restyles go through it.
        func apply(source: String, to textView: PlatformTextView) {
            let styled = styler.attributedString(for: source, theme: theme)

            #if os(iOS)
            let storage = textView.textStorage
            let previousSelection = textView.selectedRange
            storage.beginEditing()
            storage.setAttributedString(styled)
            storage.endEditing()
            textView.selectedRange = clampedSelection(previousSelection, length: styled.length)
            #elseif os(macOS)
            guard let storage = textView.textStorage else { return }
            let previousSelection = textView.selectedRange()
            storage.beginEditing()
            storage.setAttributedString(styled)
            storage.endEditing()
            textView.setSelectedRange(clampedSelection(previousSelection, length: styled.length))
            #endif

            styledTheme = theme
        }

        /// Pulls the current text out of the view, publishes it to the binding,
        /// then re-styles in place. Called from the text-did-change delegate.
        fileprivate func handleTextChanged(_ textView: PlatformTextView) {
            #if os(iOS)
            let current = textView.text ?? ""
            #elseif os(macOS)
            let current = textView.string
            #endif

            // Publish the new source to SwiftUI state first.
            if text.wrappedValue != current {
                text.wrappedValue = current
            }
            // Re-decorate the freshly edited text, keeping the caret put.
            apply(source: current, to: textView)
        }

        /// Clamps a previously captured selection range to the bounds of the new
        /// text length so restyling never produces an out-of-range selection.
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
}
#elseif os(macOS)
extension MarkdownEditor.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        handleTextChanged(textView)
    }
}
#endif
