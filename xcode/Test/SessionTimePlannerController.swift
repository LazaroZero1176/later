//
//  SessionTimePlannerController.swift
//  Later
//
//  v2.7.0 — central window listing all six session slots with reopen timer
//  status. Per-slot controls mirror the popover (off / duration / clock).
//  "Clock time…" opens `ClockTimeSheetController`. Future work: multiple
//  scheduled entries per slot with Save vs Restore actions (ISSUE roadmap).
//

import Cocoa

final class SessionTimePlannerController: NSViewController {

    private let scrollView = NSScrollView(frame: .zero)
    private let stack = NSStackView()
    private var rowPopups: [NSPopUpButton] = []
    private var rowDetailLabels: [NSTextField] = []
    private var rowTitleLabels: [NSTextField] = []

    /// Single clock editor at a time (same pattern as `ViewController`).
    private var clockSheetWindow: NSWindow?

    private var timerObserver: NSObjectProtocol?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 520))
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        let intro = NSTextField(labelWithString:
            "Plan reopen timers for each session slot. Duration timers start when you save a session to that slot; clock schedules can repeat on selected weekdays.")
        intro.font = NSFont.systemFont(ofSize: 11)
        intro.textColor = .secondaryLabelColor
        intro.maximumNumberOfLines = 0
        intro.lineBreakMode = .byWordWrapping
        intro.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(intro)
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            intro.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            intro.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            intro.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])

        buildRows()
        self.view = root

        timerObserver = NotificationCenter.default.addObserver(
            forName: .laterSessionTimersChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAllRows()
        }
    }

    deinit {
        if let o = timerObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshAllRows()
    }

    private func buildRows() {
        rowPopups = []
        rowDetailLabels = []
        rowTitleLabels = []
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for i in 0..<SessionSlotStore.slotCount {
            let slot = SessionSlotStore.slot(at: i)
            let titleStr: String
            if slot.hasSession {
                titleStr = "Slot \(i + 1) — \(slot.sessionName)"
            } else {
                titleStr = "Slot \(i + 1) — empty"
            }
            let title = NSTextField(labelWithString: titleStr)
            title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            rowTitleLabels.append(title)

            let detail = NSTextField(labelWithString: SessionTimerEditing.summary(forSlotIndex: i))
            detail.font = NSFont.systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor
            detail.maximumNumberOfLines = 0
            detail.lineBreakMode = .byWordWrapping
            rowDetailLabels.append(detail)

            let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            popUp.translatesAutoresizingMaskIntoConstraints = false
            popUp.tag = i
            popUp.target = self
            popUp.action = #selector(plannerPopupChanged(_:))
            rebuildMenu(for: popUp, slotIndex: i)
            rowPopups.append(popUp)

            let row = NSStackView(views: [title, detail, popUp])
            row.orientation = .vertical
            row.spacing = 6
            row.alignment = .leading
            row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
            row.wantsLayer = true
            row.layer?.cornerRadius = 8
            row.layer?.borderWidth = 1
            row.layer?.borderColor = NSColor.separatorColor.cgColor

            stack.addArrangedSubview(row)
        }
    }

    private enum PlannerMenuTag: Int {
        case off = 1
        case m15 = 15
        case m30 = 30
        case h1 = 60
        case h5 = 300
        case clock = 7713
    }

    private func rebuildMenu(for popUp: NSPopUpButton, slotIndex: Int) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let slot = SessionSlotStore.slot(at: slotIndex)

        func add(_ title: String, tag: Int) {
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            it.tag = tag
            menu.addItem(it)
        }

        add("Off", tag: PlannerMenuTag.off.rawValue)
        add("15 minutes after save", tag: PlannerMenuTag.m15.rawValue)
        add("30 minutes after save", tag: PlannerMenuTag.m30.rawValue)
        add("1 hour after save", tag: PlannerMenuTag.h1.rawValue)
        add("5 hours after save", tag: PlannerMenuTag.h5.rawValue)
        menu.addItem(NSMenuItem.separator())
        add("Clock time…", tag: PlannerMenuTag.clock.rawValue)

        popUp.menu = menu

        switch slot.reopenMode {
        case .off:
            popUp.selectItem(withTag: PlannerMenuTag.off.rawValue)
        case .duration:
            popUp.selectItem(withTag: slot.reopenDurationMinutes)
        case .clockTime:
            popUp.selectItem(withTag: PlannerMenuTag.clock.rawValue)
        }
    }

    private func refreshAllRows() {
        guard rowPopups.count == SessionSlotStore.slotCount,
              rowDetailLabels.count == SessionSlotStore.slotCount,
              rowTitleLabels.count == SessionSlotStore.slotCount else { return }
        for i in 0..<SessionSlotStore.slotCount {
            let slot = SessionSlotStore.slot(at: i)
            if slot.hasSession {
                rowTitleLabels[i].stringValue = "Slot \(i + 1) — \(slot.sessionName)"
            } else {
                rowTitleLabels[i].stringValue = "Slot \(i + 1) — empty"
            }
            rowDetailLabels[i].stringValue = SessionTimerEditing.summary(forSlotIndex: i)
            rebuildMenu(for: rowPopups[i], slotIndex: i)
        }
    }

    @objc private func plannerPopupChanged(_ sender: NSPopUpButton) {
        let slotIndex = sender.tag
        guard slotIndex >= 0 && slotIndex < SessionSlotStore.slotCount,
              let item = sender.selectedItem else { return }
        let tag = item.tag

        switch tag {
        case PlannerMenuTag.off.rawValue:
            SessionTimerEditing.applyOff(slotIndex: slotIndex)
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.m15.rawValue:
            SessionTimerEditing.applyDuration(slotIndex: slotIndex, minutes: 15)
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.m30.rawValue:
            SessionTimerEditing.applyDuration(slotIndex: slotIndex, minutes: 30)
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.h1.rawValue:
            SessionTimerEditing.applyDuration(slotIndex: slotIndex, minutes: 60)
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.h5.rawValue:
            SessionTimerEditing.applyDuration(slotIndex: slotIndex, minutes: 300)
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.clock.rawValue:
            // Popup may briefly show "Clock time…" before cancel/OK; snap back
            // to the on-disk mode until the sheet confirms.
            presentClockEditor(slotIndex: slotIndex)
            rebuildMenu(for: sender, slotIndex: slotIndex)
        default:
            break
        }
    }

    private func refreshRowDetail(slotIndex: Int) {
        guard slotIndex < rowDetailLabels.count else { return }
        rowDetailLabels[slotIndex].stringValue = SessionTimerEditing.summary(forSlotIndex: slotIndex)
    }

    private func presentClockEditor(slotIndex: Int) {
        if let w = clockSheetWindow, w.isVisible {
            w.close()
        }
        let slot = SessionSlotStore.slot(at: slotIndex)
        let titleSuffix: String
        if slot.hasSession {
            titleSuffix = "Slot \(slotIndex + 1) — \(slot.sessionName)"
        } else {
            titleSuffix = "Slot \(slotIndex + 1) — empty"
        }
        let sheet = ClockTimeSheetController(
            initialHour: slot.reopenClockHour,
            initialMinute: slot.reopenClockMinute,
            initialWeekdays: Set(slot.reopenWeekdays)
        )
        sheet.onConfirm = { [weak self] hour, minute, weekdays in
            SessionTimerEditing.applyClockTime(
                slotIndex: slotIndex,
                hour: hour,
                minute: minute,
                weekdays: weekdays
            )
            self?.clockSheetWindow = nil
        }
        sheet.onCancel = { [weak self] in
            self?.refreshAllRows()
            self?.clockSheetWindow = nil
        }
        sheet.onWindowClosed = { [weak self] in
            self?.clockSheetWindow = nil
        }
        let win = NSWindow(contentViewController: sheet)
        win.title = "Reopen schedule — \(titleSuffix)"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 400, height: 300))
        win.center()
        clockSheetWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
