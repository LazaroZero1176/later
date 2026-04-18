//
//  ClockTimeSheetController.swift
//  Later
//
//  Small programmatic sheet for picking a wall-clock reopen time plus an
//  optional weekday recurrence pattern. Used by `ViewController` when the
//  user picks "At specific time…" from the per-slot time dropdown (v2.6.0).
//
//  Kept storyboard-less to keep the footprint small and to match the style
//  of `ShortcutSettingsController` (also programmatic).
//

import Cocoa

final class ClockTimeSheetController: NSViewController {

    /// Completion handler invoked on OK with the chosen values. Weekday
    /// values use `Calendar.weekday` (1=Sun ... 7=Sat). An empty set means
    /// the schedule is one-shot (next occurrence of HH:MM, then done).
    var onConfirm: ((_ hour: Int, _ minute: Int, _ weekdays: Set<Int>) -> Void)?
    /// Invoked on Cancel (or ESC). The caller uses this to roll the time
    /// dropdown back to whatever selection the slot actually holds.
    var onCancel: (() -> Void)?

    private let initialHour: Int
    private let initialMinute: Int
    private let initialWeekdays: Set<Int>

    private let datePicker = NSDatePicker()
    private var weekdayCheckboxes: [NSButton] = []
    private let dailyButton = NSButton()

    /// Displayed in the fixed order Mon...Sun to match the tooltip output.
    /// The stored Calendar.weekday values (1=Sun) are tracked separately in
    /// `weekdayValues[]` so we don't need locale-aware reshuffling.
    private let weekdayTitles = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let weekdayValues = [2, 3, 4, 5, 6, 7, 1]

    init(initialHour: Int, initialMinute: Int, initialWeekdays: Set<Int>) {
        self.initialHour = initialHour
        self.initialMinute = initialMinute
        self.initialWeekdays = initialWeekdays
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))

        let title = NSTextField(labelWithString: "Reopen this session")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.hourMinute]
        datePicker.dateValue = initialDateForPicker()
        datePicker.controlSize = .regular

        let timeRow = NSStackView(views: [
            NSTextField(labelWithString: "Time:"),
            datePicker
        ])
        timeRow.orientation = .horizontal
        timeRow.spacing = 8

        let weekdayLabel = NSTextField(labelWithString: "Repeat on:")
        weekdayLabel.font = NSFont.systemFont(ofSize: 12)

        var boxes: [NSButton] = []
        for (i, t) in weekdayTitles.enumerated() {
            let cb = NSButton(checkboxWithTitle: t, target: self, action: #selector(weekdayToggled(_:)))
            cb.tag = weekdayValues[i]
            if initialWeekdays.contains(weekdayValues[i]) {
                cb.state = .on
            }
            boxes.append(cb)
        }
        weekdayCheckboxes = boxes

        let weekdayRow = NSStackView(views: boxes)
        weekdayRow.orientation = .horizontal
        weekdayRow.spacing = 6
        weekdayRow.distribution = .fillEqually

        dailyButton.setButtonType(.momentaryPushIn)
        dailyButton.bezelStyle = .rounded
        dailyButton.title = "Daily"
        dailyButton.target = self
        dailyButton.action = #selector(dailyClicked(_:))

        let noneButton = NSButton(title: "Clear", target: self, action: #selector(noneClicked(_:)))
        noneButton.bezelStyle = .rounded

        let quickRow = NSStackView(views: [dailyButton, noneButton])
        quickRow.orientation = .horizontal
        quickRow.spacing = 6

        let hint = NSTextField(labelWithString: "Leave unchecked for a one-shot reopen at the chosen time.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(okClicked(_:)))
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [NSView(), cancel, ok])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fill

        let column = NSStackView(views: [
            title,
            timeRow,
            weekdayLabel,
            weekdayRow,
            quickRow,
            hint,
            buttonRow
        ])
        column.orientation = .vertical
        column.spacing = 10
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            buttonRow.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            buttonRow.leadingAnchor.constraint(equalTo: column.leadingAnchor)
        ])

        self.view = root
    }

    // MARK: - Actions

    @objc private func weekdayToggled(_ sender: NSButton) {
        // Nothing to persist here; the state is pulled in `currentWeekdays()`
        // on OK. The empty method is a safe target so the checkbox animates.
        _ = sender
    }

    @objc private func dailyClicked(_ sender: Any?) {
        for cb in weekdayCheckboxes { cb.state = .on }
    }

    @objc private func noneClicked(_ sender: Any?) {
        for cb in weekdayCheckboxes { cb.state = .off }
    }

    @objc private func cancelClicked(_ sender: Any?) {
        onCancel?()
        dismiss(nil)
    }

    @objc private func okClicked(_ sender: Any?) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: datePicker.dateValue)
        let h = comps.hour ?? initialHour
        let m = comps.minute ?? initialMinute
        onConfirm?(h, m, currentWeekdays())
        dismiss(nil)
    }

    // MARK: - Helpers

    private func initialDateForPicker() -> Date {
        var comps = DateComponents()
        comps.hour = initialHour
        comps.minute = initialMinute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func currentWeekdays() -> Set<Int> {
        var out = Set<Int>()
        for cb in weekdayCheckboxes where cb.state == .on {
            out.insert(cb.tag)
        }
        return out
    }
}
