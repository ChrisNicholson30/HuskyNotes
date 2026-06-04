//
//  FormatAccessoryView.swift
//  HuskyNotes
//
//  The iOS / iPadOS formatting toolbar shown above the keyboard. macOS gets the
//  same actions from the menu bar (⌘B etc.); on touch devices this scrollable
//  strip of buttons is how you reach them. Each button drives a `MarkdownCommand`
//  applied to the focused editor.
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

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 48)
    }

    // MARK: Build

    private func build() {
        let done = button(symbol: "keyboard.chevron.compact.down", label: "Done") { [weak self] in
            self?.onDone()
        }
        done.translatesAutoresizingMaskIntoConstraints = false
        addSubview(done)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        stack.addArrangedSubview(headingButton())
        for spec in Self.specs {
            stack.addArrangedSubview(button(symbol: spec.symbol, label: spec.label) { [weak self] in
                self?.onCommand(spec.command)
            })
        }

        NSLayoutConstraint.activate([
            done.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            done.centerYAnchor.constraint(equalTo: centerYAnchor),

            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }

    /// The ordered inline/line commands shown after the heading menu.
    private static let specs: [(symbol: String, command: MarkdownCommand, label: String)] = [
        ("bold", .bold, "Bold"),
        ("italic", .italic, "Italic"),
        ("strikethrough", .strikethrough, "Strikethrough"),
        ("chevron.left.forwardslash.chevron.right", .inlineCode, "Code"),
        ("list.bullet", .bulletList, "Bullet list"),
        ("list.number", .orderedList, "Numbered list"),
        ("checklist", .todo, "To-do"),
        ("text.quote", .quote, "Quote"),
        ("link", .link, "Link")
    ]

    private func button(symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11)
        let b = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        b.accessibilityLabel = label
        return b
    }

    /// A heading button presenting an H1–H3 / Body menu.
    private func headingButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "textformat.size")
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11)
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
}
#endif
