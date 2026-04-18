import Cocoa
import KeyboardShortcuts

/// Minimal settings panel for the eight global shortcuts introduced in
/// v2.5.0. Built programmatically — no storyboard — so it's easy to keep in
/// sync with the `KeyboardShortcuts.Name` list in `Shortcuts.swift`.
///
/// Semantics:
///   - The `KeyboardShortcuts` recorders write every edit to `UserDefaults`
///     *immediately*. To give users a classic Save / Cancel experience,
///     the controller snapshots every shortcut when the window opens and
///     restores that snapshot on Cancel (or on titlebar-X, which routes
///     through the same path via `NSWindowDelegate.windowShouldClose`).
///   - Save simply hides the window — nothing to commit, the recordings
///     are already persisted.
///   - The window is *hidden* (`orderOut(nil)`) rather than closed, so the
///     app never loses its last window. On accessory configurations (no
///     Dock icon) AppKit would otherwise consider the app quittable when
///     the final window goes away.
final class ShortcutSettingsController: NSViewController, NSWindowDelegate {

    private let windowWidth: CGFloat = 460
    private let rowSpacing: CGFloat = 10
    private let labelColumnWidth: CGFloat = 210

    /// Snapshot taken on `viewWillAppear` — restored on Cancel.
    /// `nil` value means "no shortcut set for that name at open time".
    private var initialShortcuts: [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut?] = [:]

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

        // Button row — Cancel (secondary) + Save (default, Return key).
        // Right-aligned so it matches standard macOS dialogs.
        let spacer = NSBox()
        spacer.boxType = .separator
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spacer)
        NSLayoutConstraint.activate([
            spacer.widthAnchor.constraint(equalToConstant: windowWidth - 40)
        ])

        let buttonRow = NSStackView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Return

        let leftSpacer = NSView()
        leftSpacer.translatesAutoresizingMaskIntoConstraints = false
        leftSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        buttonRow.addArrangedSubview(leftSpacer)
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(saveButton)

        stack.addArrangedSubview(buttonRow)
        NSLayoutConstraint.activate([
            buttonRow.widthAnchor.constraint(equalToConstant: windowWidth - 40)
        ])

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: windowWidth)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        snapshotCurrentShortcuts()
        view.window?.delegate = self
    }

    // MARK: - Snapshot / restore

    private func snapshotCurrentShortcuts() {
        initialShortcuts.removeAll(keepingCapacity: true)
        for name in KeyboardShortcuts.Name.allAppShortcuts {
            initialShortcuts[name] = KeyboardShortcuts.getShortcut(for: name)
        }
    }

    private func restoreSnapshot() {
        for (name, shortcut) in initialShortcuts {
            KeyboardShortcuts.setShortcut(shortcut, for: name)
        }
    }

    // MARK: - Actions

    @objc private func saveClicked() {
        // Edits are already persisted by the recorder — nothing to commit.
        // Refresh the snapshot so a subsequent open can still Cancel.
        snapshotCurrentShortcuts()
        view.window?.orderOut(nil)
    }

    @objc private func cancelClicked() {
        restoreSnapshot()
        view.window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// Route the titlebar close button through Cancel semantics and keep
    /// the window alive (`orderOut` instead of true close) so AppKit
    /// doesn't treat it as a terminal event on accessory-mode launches.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        restoreSnapshot()
        sender.orderOut(nil)
        return false
    }

    // MARK: - Row builder

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
