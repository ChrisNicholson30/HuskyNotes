//
//  FormatAccessoryView.swift
//  HuskyNotes
//
//  The iOS / iPadOS formatting toolbar shown above the keyboard. macOS gets the
//  same actions from the menu bar (⌘B etc.); on touch devices this row of buttons
//  is how you reach them. The common actions sit inline (evenly distributed so the
//  row fits any iPhone width without scrolling or clipping); the rest live in a
//  "More" (•••) dropdown. Each button drives a `MarkdownCommand` on the editor.
//

#if os(iOS)
import UIKit

/// A keyboard-accessory toolbar of Markdown formatting buttons.
final class FormatAccessoryView: UIView {

    private let onCommand: (MarkdownCommand) -> Void
    private let onDone: () -> Void

    /// - Parameters:
    ///   - onCommand: invoked with the chosen command (applied to the editor).
    ///   - onDone: invoked to dismiss the keyboard.
    init(onCommand: @escaping (MarkdownCommand) -> Void, onDone: @escaping () -> Void) {
        self.onCommand = onCommand
        self.onDone = onDone
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48))
        autoresizingMask = .flexibleWidth
        backgroundColor = .secondarySystemBackground
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The height of the button row itself (excluding any safe-area padding).
    private static let barHeight: CGFloat = 48

    override var intrinsicContentSize: CGSize {
        // When the bar is pinned to the bottom edge (hardware keyboard, or the
        // software keyboard dismissed), iOS reports the home-indicator inset as
        // our bottom safe area. Grow by it so the buttons clear the rounded
        // corner; the background still fills to the very edge.
        CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight + safeAreaInsets.bottom)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        // The bottom inset toggles as the bar moves above the keyboard vs. the
        // home indicator — re-measure so the extra padding appears/disappears.
        invalidateIntrinsicContentSize()
    }

    // MARK: Build

    private func build() {
        let stack = UIStackView()
        stack.axis = .horizontal
        // Equal widths so the whole row always fits the screen, evenly spaced,
        // with nothing scrolled off or clipped at the rounded corners.
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(headingButton())
        stack.addArrangedSubview(highlightButton())
        for spec in Self.primarySpecs {
            stack.addArrangedSubview(button(symbol: spec.symbol, label: spec.label) { [weak self] in
                self?.onCommand(spec.command)
            })
        }
        stack.addArrangedSubview(moreButton())
        stack.addArrangedSubview(button(symbol: "keyboard.chevron.compact.down", label: "Done") { [weak self] in
            self?.onDone()
        })

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -4),
            // Pin to the safe area so the row sits above the home indicator,
            // leaving the bottom inset as background-only padding.
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    /// The common formatting buttons shown inline (after the heading + highlight
    /// menus, before the "More" overflow).
    private static let primarySpecs: [(symbol: String, command: MarkdownCommand, label: String)] = [
        ("bold", .bold, "Bold"),
        ("italic", .italic, "Italic"),
        ("strikethrough", .strikethrough, "Strikethrough"),
        ("list.bullet", .bulletList, "Bullet List")
    ]

    /// The less-frequent commands tucked into the "More" (•••) dropdown.
    private static let moreSpecs: [(symbol: String, command: MarkdownCommand, label: String)] = [
        ("chevron.left.forwardslash.chevron.right", .inlineCode, "Inline Code"),
        ("list.number", .orderedList, "Numbered List"),
        ("checklist", .todo, "To-Do"),
        ("text.quote", .quote, "Quote"),
        ("tablecells", .table, "Table"),
        ("link", .link, "Link"),
        ("minus", .lineSeparator, "Line Separator")
    ]

    private func button(symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        let b = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        b.accessibilityLabel = label
        return b
    }

    /// The "More" overflow button presenting the less-common commands as a menu.
    private func moreButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "ellipsis.circle")
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        let b = UIButton(configuration: config)
        b.accessibilityLabel = "More"
        b.menu = UIMenu(children: Self.moreSpecs.map { spec in
            UIAction(title: spec.label, image: UIImage(systemName: spec.symbol)) { [weak self] _ in
                self?.onCommand(spec.command)
            }
        })
        b.showsMenuAsPrimaryAction = true
        return b
    }

    /// A heading button presenting an H1–H3 / Body menu.
    private func headingButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "textformat.size")
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        let b = UIButton(configuration: config)
        b.accessibilityLabel = "Heading"
        b.menu = UIMenu(children: [
            UIAction(title: "Heading 1") { [weak self] _ in self?.onCommand(.heading(1)) },
            UIAction(title: "Heading 2") { [weak self] _ in self?.onCommand(.heading(2)) },
            UIAction(title: "Heading 3") { [weak self] _ in self?.onCommand(.heading(3)) },
            UIAction(title: "Body Text") { [weak self] _ in self?.onCommand(.heading(0)) }
        ])
        b.showsMenuAsPrimaryAction = true
        return b
    }

    /// A highlighter button presenting the fluorescent colour palette plus a
    /// "Remove" action. Each colour shows a swatch of its actual fill.
    private func highlightButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "highlighter")
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        let b = UIButton(configuration: config)
        b.accessibilityLabel = "Highlight"

        let colors: [UIMenuElement] = HighlightColor.allCases.map { color in
            UIAction(title: color.displayName, image: Self.swatch(color)) { [weak self] _ in
                self?.onCommand(.highlight(color))
            }
        }
        let remove = UIAction(title: "Remove Highlight", image: UIImage(systemName: "xmark")) { [weak self] _ in
            self?.onCommand(.removeHighlight)
        }
        b.menu = UIMenu(children: [
            UIMenu(title: "", options: .displayInline, children: colors),
            remove
        ])
        b.showsMenuAsPrimaryAction = true
        return b
    }

    /// A small filled circle in a highlighter colour, for menu rows.
    private static func swatch(_ color: HighlightColor) -> UIImage? {
        UIImage(systemName: "circle.fill")?
            .withTintColor(color.fill.platformColor, renderingMode: .alwaysOriginal)
    }
}
#endif
