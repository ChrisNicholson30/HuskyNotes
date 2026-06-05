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

// MARK: - EditorController

/// A lightweight handle that lets a parent view drive the live editor — e.g.
/// inserting an attachment reference at the current caret. The editor's
/// coordinator registers its implementation when the text view is created;
/// calls made before that (or after teardown) are simply ignored.
@MainActor
final class EditorController {
    /// Set by the coordinator; inserts Markdown at the caret / over the selection.
    fileprivate var insertHandler: ((String) -> Void)?

    /// Set by the coordinator; makes the editor first responder (opens the
    /// keyboard on iOS).
    fileprivate var focusHandler: (() -> Void)?

    /// Inserts `markdown` at the current caret in the focused editor.
    func insert(_ markdown: String) { insertHandler?(markdown) }

    /// Focuses the editor so the user can type immediately (and the iOS keyboard
    /// appears).
    func focus() { focusHandler?() }
}

// MARK: - MarkdownEditor

#if os(iOS)

/// SwiftUI wrapper around a TextKit 2 `UITextView` providing live Markdown
/// source styling for iOS and iPadOS.
struct MarkdownEditor: UIViewRepresentable {

    /// The canonical Markdown source. Mutated as the user types.
    @Binding var text: String

    /// The active theme supplying every colour, font and metric.
    let theme: Theme

    /// Optional handle for parent-driven insertion (e.g. attachments at caret).
    var controller: EditorController? = nil

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
        controller?.insertHandler = { [weak coordinator = context.coordinator] markdown in
            coordinator?.insertAtCaret(markdown)
        }
        controller?.focusHandler = { [weak textView] in
            textView?.becomeFirstResponder()
        }

        // A scrollable formatting toolbar above the keyboard (iPhone/iPad), since
        // the menu-bar Format commands only exist on macOS.
        textView.inputAccessoryView = FormatAccessoryView(
            onCommand: { [weak coordinator = context.coordinator] command in
                coordinator?.perform(command)
            },
            onDone: { [weak textView] in textView?.resignFirstResponder() }
        )

        // Tap a rendered checkbox to toggle it (additive — doesn't block editing).
        // It recognises *simultaneously* with the text view's own tap gesture
        // (via the coordinator delegate) so a single tap still places the caret —
        // without it, this recogniser swallows the tap and you'd need a long press.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCheckboxTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
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

    /// Optional handle for parent-driven insertion (e.g. attachments at caret).
    var controller: EditorController? = nil

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
        // A modest leading/trailing gutter now that the column is left-aligned
        // (no longer centred with large margins on wide windows).
        textView.textContainerInset = NSSize(width: 20, height: 16)
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
        controller?.insertHandler = { [weak coordinator = context.coordinator] markdown in
            coordinator?.insertAtCaret(markdown)
        }
        controller?.focusHandler = { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
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

        /// Element ranges (from the last styling) whose markers reveal while the
        /// caret is inside them — now just links, whose URL must stay editable.
        /// (Emphasis/code/heading/quote markers are always concealed, so they
        /// never need a caret-driven re-style.) Lets `handleSelectionChanged`
        /// re-style only when the caret crosses one of these boundaries — never on
        /// plain caret moves, which were fighting the user's taps, pasting and
        /// caret placement. Empty for notes without links, so the caret glides.
        private var concealElements: [NSRange] = []

        /// The elements currently revealed (those the caret is inside); a re-style
        /// is needed only when this set changes.
        private var lastRevealSignature: [NSRange] = []

        /// Ranges of concealed *trailing* delimiters from the last styling (closing
        /// `**`, `` ` ``, `</mark>`, …). They're zero-width, so the caret sits just
        /// before them at a span's visual end; `adjustedReturnLocation` skips a
        /// Return past them so the closing marker isn't pushed onto the next line.
        private var trailingHiddenMarkers: [NSRange] = []

        /// The last caret/selection seen *while the editor was first responder*.
        /// Parent-driven insertions (attachments) fall back to this: presenting a
        /// file importer resigns first responder and collapses the live selection
        /// to the document end, which is why attachments were landing at the bottom.
        private var lastSelection: NSRange?

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
            let styled = styler.attributedString(for: source, theme: theme, caret: desired)
            concealElements = styled.concealElements
            trailingHiddenMarkers = styled.trailingHiddenMarkers
            lastRevealSignature = revealSignature(for: desired)

            #if os(iOS)
            let storage = textView.textStorage
            #elseif os(macOS)
            guard let storage = textView.textStorage else { return }
            #endif

            // When the characters are unchanged (every keystroke / theme switch),
            // update only the *attributes* in place. Replacing the whole string
            // tears down the insertion point on macOS — pressing Return would make
            // the caret vanish until you clicked again.
            restyle(storage, with: styled.attributed, sameCharacters: storage.string == source)

            let clamped = clampedSelection(desired, length: styled.attributed.length)
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

        /// Re-conceals/reveals markers when the caret moves to a different
        /// paragraph. Within the same paragraph it does nothing, so tapping,
        /// selecting and pasting aren't disrupted by a re-style that would reset
        /// the caret. The re-style is deferred to the next runloop so it never
        /// mutates the text storage *during* a tap that's grabbing first responder
        /// (which would drop focus and leave the note feeling "uneditable").
        fileprivate func handleSelectionChanged(_ textView: PlatformTextView) {
            guard !isApplying, !hasMarkedText(textView) else { return }
            // Remember where the user actually is, so an attachment inserted after
            // a file picker (which drops first responder) lands at the caret — not
            // at the end of the note.
            if isFirstResponder(textView) {
                lastSelection = currentSelection(of: textView)
            }
            // Only re-style when the caret crosses into/out of a styled span,
            // which is the only time the concealment must change. Moving within
            // plain text (or within the same span) leaves the signature unchanged.
            let signature = revealSignature(for: currentSelection(of: textView))
            if signature == lastRevealSignature { return }
            lastRevealSignature = signature
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, !self.isApplying, !self.hasMarkedText(textView) else { return }
                self.apply(source: self.currentText(of: textView), to: textView)
            }
        }

        /// The elements whose markers should be revealed for `caret` (those it
        /// touches). Re-styling is needed only when this set changes.
        private func revealSignature(for caret: NSRange) -> [NSRange] {
            concealElements.filter { MarkdownStyler.caret(caret, touches: $0) }
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

        /// Continues a Markdown list when Return is pressed inside a list item
        /// (next bullet/number, or end the list on an empty item). Returns
        /// `true` if it handled the newline; `false` to let the editor insert a
        /// normal newline.
        fileprivate func continueListOnReturn(in textView: PlatformTextView) -> Bool {
            let current = currentText(of: textView)
            let selection = currentSelection(of: textView)
            guard let result = MarkdownFormatting.handleReturn(text: current, selection: selection) else {
                return false
            }
            text.wrappedValue = result.text
            apply(source: result.text, to: textView, selection: result.selection)
            return true
        }

        /// The location at which a newline should be inserted for a Return pressed
        /// with the caret at `location`: any concealed *trailing* delimiters
        /// immediately following the caret are skipped, so the newline lands
        /// *after* the whole styled span rather than splitting it (which would
        /// strand the closing `**`/`` ` `` on the next line). Returns `location`
        /// unchanged when no trailing markers follow it.
        private func adjustedReturnLocation(for location: Int) -> Int {
            var loc = location
            var advanced = true
            while advanced {
                advanced = false
                for marker in trailingHiddenMarkers where marker.location == loc && marker.length > 0 {
                    loc = marker.location + marker.length
                    advanced = true
                    break
                }
            }
            return loc
        }

        /// Inserts a newline at `location`, publishing the change and restyling with
        /// the caret on the new line. Used when a Return must be redirected past
        /// concealed trailing delimiters so the span stays intact.
        fileprivate func insertNewline(at location: Int, in textView: PlatformTextView) {
            let ns = currentText(of: textView) as NSString
            let loc = min(max(location, 0), ns.length)
            let m = NSMutableString(string: ns)
            m.insert("\n", at: loc)
            let newText = m as String
            text.wrappedValue = newText
            apply(source: newText, to: textView, selection: NSRange(location: loc + 1, length: 0))
        }

        /// Whether a Return with a collapsed caret at `location` needs redirecting
        /// past concealed trailing delimiters; returns the adjusted location, or
        /// `nil` if a normal newline at `location` is fine.
        fileprivate func returnRedirect(forCaretAt location: Int) -> Int? {
            let adjusted = adjustedReturnLocation(for: location)
            return adjusted == location ? nil : adjusted
        }

        /// Inserts an attachment reference (or any Markdown) at the caret,
        /// placing it on its own line, then restyles. Driven by `EditorController`.
        func insertAtCaret(_ markdown: String) {
            guard let textView else { return }
            // Prefer the live caret while focused; otherwise the last caret seen
            // while focused (a file importer resigns first responder and collapses
            // the live selection to the document end).
            let selection = isFirstResponder(textView)
                ? currentSelection(of: textView)
                : (lastSelection ?? currentSelection(of: textView))
            let result = MarkdownFormatting.insertAttachment(
                markdown,
                into: currentText(of: textView),
                at: selection
            )
            text.wrappedValue = result.text
            apply(source: result.text, to: textView, selection: result.selection)
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
    /// Intercepts a plain Return to continue a list; all other edits proceed
    /// normally.
    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
        guard text == "\n", textView.markedTextRange == nil else { return true }

        // Re-entrancy note: mutating the text storage inside `shouldChangeTextIn`
        // (while UIKit is mid-edit and we're cancelling its insert) can corrupt the
        // text view's state — so we block the default newline (`return false`) and
        // perform our own edit on the next runloop.

        // 1. Continue a Markdown list when the caret is in a list item.
        if MarkdownFormatting.handleReturn(text: currentText(of: textView), selection: range) != nil {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                _ = self.continueListOnReturn(in: textView)
            }
            return false
        }

        // 2. Otherwise, if concealed trailing delimiters follow a collapsed caret,
        //    redirect the newline past them so the closing marker isn't stranded on
        //    the next line. A ranged Return just replaces the selection normally.
        if range.length == 0, let redirect = returnRedirect(forCaretAt: range.location) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.insertNewline(at: redirect, in: textView)
            }
            return false
        }

        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        handleTextChanged(textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        handleSelectionChanged(textView)
    }
}

extension MarkdownEditor.Coordinator: UIGestureRecognizerDelegate {
    /// Recognise the checkbox tap *alongside* the text view's built-in gestures,
    /// so a single tap still positions the caret rather than being swallowed
    /// (which forced a long press before the caret appeared).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#elseif os(macOS)
extension MarkdownEditor.Coordinator: NSTextViewDelegate {
    /// Intercepts the Return key to continue a list; returns `true` to consume
    /// it, `false` to let `NSTextView` insert a normal newline.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              !textView.hasMarkedText() else { return false }

        // Continue a Markdown list if the caret is in a list item.
        if continueListOnReturn(in: textView) { return true }

        // Otherwise redirect the newline past any concealed trailing delimiters so
        // the closing marker isn't stranded on the next line.
        let selection = textView.selectedRange()
        if selection.length == 0, let redirect = returnRedirect(forCaretAt: selection.location) {
            insertNewline(at: redirect, in: textView)
            return true
        }
        return false
    }

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
