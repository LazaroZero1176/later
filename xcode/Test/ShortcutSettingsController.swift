import Cocoa
import KeyboardShortcuts

/// Minimal settings panel for the eight global shortcuts introduced in
/// v2.5.0. Built programmatically — no storyboard — so it's easy to keep in
/// sync with the `KeyboardShortcuts.Name` list in `Shortcuts.swift`.
///
/// Layout:
///     ┌────────────────────────────────────────────────────┐
///     │ These shortcuts work from any app. Click a field   │
///     │ and press the keys you want; use the X to clear.   │
///     │                                                    │
///     │ Save active session         [  ⌘⇧L     ⌫ ]        │
///     │ Restore active session      [  ⌘⇧R     ⌫ ]        │
///     │ Restore Slot 1 (Work)       [  none    ⌫ ]        │
///     │ …                                                  │
///     └────────────────────────────────────────────────────┘
final class ShortcutSettingsController: NSViewController {

    private let windowWidth: CGFloat = 440
    private let rowSpacing: CGFloat = 10
    private let labelColumnWidth: CGFloat = 210

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: 400))
        root.translatesAutoresizingMaskIntoConstraints = true
        self.view = root

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = rowSpacing
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        root.addSubview(stack)

        let header = NSTextField(wrappingLabelWithString:
            "These shortcuts work from any app. Click a field and press the keys you want; use the X to clear. An empty field means no shortcut.")
        header.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        header.textColor = .secondaryLabelColor
        header.preferredMaxLayoutWidth = windowWidth - 40
        stack.addArrangedSubview(header)

        stack.addArrangedSubview(makeRow(label: "Save active session",
                                         name: .saveActiveSession))
        stack.addArrangedSubview(makeRow(label: "Restore active session",
                                         name: .restoreActiveSession))

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: windowWidth - 40)
        ])

        for (i, name) in KeyboardShortcuts.Name.allSlotRestore.enumerated() {
            let slot = SessionSlotStore.slot(at: i)
            let sessionDescription = slot.hasSession ? slot.sessionName : "empty"
            let label = "Restore Slot \(i + 1) (\(sessionDescription))"
            stack.addArrangedSubview(makeRow(label: label, name: name))
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: windowWidth)
        ])
    }

    private func makeRow(label: String, name: KeyboardShortcuts.Name) -> NSView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let labelField = NSTextField(labelWithString: label)
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.lineBreakMode = .byTruncatingTail
        labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        recorder.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(labelField)
        row.addArrangedSubview(recorder)

        NSLayoutConstraint.activate([
            labelField.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])

        return row
    }
}
