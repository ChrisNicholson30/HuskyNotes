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

        // A scrollable formatting toolbar above the keyboard (iPhone/iPad), since
        // the menu-bar Format commands only exist on macOS.
        textView.inputAccessoryView = FormatAccessoryView(
            onCommand: { [weak coordinator = context.coordinator] command in
                coordinator?.perform(command)
            },
            onDone: { [weak textView] in textView?.resignFirstResponder() }
        )

        // Tap a rendered checkbox to toggle it (additive — doesn't block editing).
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCheckboxTap(_:))
        )
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)

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
        let textView = CheckboxTextView(usingTextLayoutManager: true)
        textView.onCheckboxClick = { [weak coordinator = context.coordinator] index in
            coordinator?.toggleCheckbox(atCharacterIndex: index) ?? false
        }
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

/// An `NSTextView` that lets a click on a rendered checkbox toggle it before
/// falling back to normal caret placement.
final class CheckboxTextView: NSTextView {
    /// Returns `true` if the click at the given character index toggled a
    /// checkbox (and should be consumed).
    var onCheckboxClick: ((Int) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if onCheckboxClick?(index) == true { return }
        super.mouseDown(with: event)
    }
}

#endif

// MARK: - Coordinator

extension MarkdownEditor {

    /// Bridges the platform text view's editing callbacks back to SwiftUI and
    /// owns the (re-)styling of the text storage. Shared between the iOS and
    /// macOS representables — only the delegate conformance differs.
    ///
    /// `@MainActor` because every entry point (representable callbacks, text-view
    /// delegate methods, gesture/menu handlers) runs on the main thread and
    /// touches main-actor-isolated UIKit/AppKit views.
    @MainActor
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
            #elseif os(macOS)
            guard let storage = textView.textStorage else { return }
            #endif

            // When the characters are unchanged (every keystroke / theme switch),
            // update only the *attributes* in place. Replacing the whole string
            // tears down the insertion point on macOS — pressing Return would make
            // the caret vanish until you clicked again.
            restyle(storage, with: styled, sameCharacters: storage.string == source)

            let clamped = clampedSelection(desired, length: styled.length)
            #if os(iOS)
            textView.selectedRange = clamped
            #elseif os(macOS)
            textView.setSelectedRange(clamped)
            // Keep the caret visible and blinking after a restyle.
            textView.updateInsertionPointStateAndRestartTimer(true)
            #endif

            styledTheme = theme
        }

        /// Applies `styled`'s attributes to `storage`. If the underlying string is
        /// unchanged, only attributes are rewritten (preserving the insertion
        /// point); otherwise the whole attributed string is replaced.
        private func restyle(_ storage: NSTextStorage, with styled: NSAttributedString, sameCharacters: Bool) {
            storage.beginEditing()
            if sameCharacters {
                let full = NSRange(location: 0, length: styled.length)
                styled.enumerateAttributes(in: full, options: []) { attributes, range, _ in
                    storage.setAttributes(attributes, range: range)
                }
            } else {
                storage.setAttributedString(styled)
            }
            storage.endEditing()
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
            perform(command, on: textView)
        }

        /// Applies a formatting command to this editor's text view. Used by the
        /// iOS keyboard accessory toolbar (which targets this exact editor).
        func perform(_ command: MarkdownCommand) {
            guard let textView else { return }
            perform(command, on: textView)
        }

        /// The shared formatting path: rewrite the source + selection and restyle.
        private func perform(_ command: MarkdownCommand, on textView: PlatformTextView) {
            let result = MarkdownFormatting.apply(
                command,
                to: currentText(of: textView),
                selection: currentSelection(of: textView)
            )
            text.wrappedValue = result.text
            apply(source: result.text, to: textView, selection: result.selection)
        }

        /// Toggles the `[ ]` ↔ `[x]` checkbox on the line containing `index`, but
        /// only when `index` is within the marker zone (so tapping the text body
        /// doesn't toggle). Returns whether a toggle happened.
        @discardableResult
        func toggleCheckbox(atCharacterIndex index: Int) -> Bool {
            guard let textView else { return false }
            let ns = currentText(of: textView) as NSString
            guard ns.length > 0, index >= 0, index <= ns.length else { return false }

            let line = ns.lineRange(for: NSRange(location: min(index, ns.length - 1), length: 0))
            let end = line.location + line.length

            var i = line.location
            while i < end, ns.character(at: i) == 32 || ns.character(at: i) == 9 { i += 1 }
            guard i < end else { return false }
            let bullet = ns.character(at: i)
            guard bullet == 45 || bullet == 42 || bullet == 43 else { return false } // - * +
            guard i + 4 < end,
                  ns.character(at: i + 1) == 32,
                  ns.character(at: i + 2) == 91,  // [
                  ns.character(at: i + 4) == 93   // ]
            else { return false }

            let contentStart = i + 6
            guard index < contentStart else { return false } // only the marker zone toggles

            let markIndex = i + 3
            let newMark = ns.character(at: markIndex) == 32 ? "x" : " "
            let mutable = NSMutableString(string: ns)
            mutable.replaceCharacters(in: NSRange(location: markIndex, length: 1), with: newMark)
            let newText = mutable as String

            // Toggling re-styles the whole document, which would otherwise scroll
            // the view to the caret. Capture and restore the scroll position so
            // the tapped line stays put.
            let selection = currentSelection(of: textView)
            #if os(iOS)
            let savedOffset = textView.contentOffset
            #endif
            text.wrappedValue = newText
            apply(source: newText, to: textView, selection: selection)
            #if os(iOS)
            textView.setContentOffset(savedOffset, animated: false)
            #endif
            return true
        }

        #if os(iOS)
        @objc fileprivate func handleCheckboxTap(_ gesture: UITapGestureRecognizer) {
            guard let textView else { return }
            let point = gesture.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            toggleCheckbox(atCharacterIndex: index)
        }
        #endif

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
