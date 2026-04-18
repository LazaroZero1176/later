//
//  SessionTimePlannerController.swift
//  Later
//
//  v2.7.0 — central window listing all six session slots with reopen timer
//  status. Edits are held in memory until Save; Cancel discards. Per-slot
//  controls mirror the popover (off / duration / clock). "Clock time…"
//  opens `ClockTimeSheetController`.
//

import Cocoa

final class SessionTimePlannerController: NSViewController, NSWindowDelegate {

    /// Two columns × three rows of slot cards; wide enough for narrow labels per cell.
    private let contentWidth: CGFloat = 720
    /// NSScrollView has no intrinsic height; without this, the layout chain
    /// collapses and the window can shrink to a useless strip (no slot list).
    private let minScrollAreaHeight: CGFloat = 400
    private let minWindowContentHeight: CGFloat = 580

    private let scrollView = NSScrollView(frame: .zero)
    private let stack = NSStackView()
    private var rowPopups: [NSPopUpButton] = []
    private var rowDetailLabels: [NSTextField] = []
    private var rowSaveDetailLabels: [NSTextField] = []
    private var saveRowPopups: [NSPopUpButton] = []
    private var rowTitleLabels: [NSTextField] = []

    /// Draft copy — committed on Save only.
    private var draftSlots: [SessionSlotStore.Slot] = []

    /// Single clock editor at a time (same pattern as `ViewController`).
    private var clockSheetWindow: NSWindow?
    private var saveClockSheetWindow: NSWindow?

    private var timerObserver: NSObjectProtocol?

    override func loadView() {
        draftSlots = SessionSlotStore.allSlots()

        let root = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 600))
        root.translatesAutoresizingMaskIntoConstraints = false

        let intro = NSTextField(wrappingLabelWithString:
            "Each card: Restore = run Restore at the set time. Scheduled save = capture the desktop into this slot (Save windows for later) at clock time — e.g. morning save, evening restore. Apply with Save.")
        intro.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        intro.textColor = .secondaryLabelColor
        intro.preferredMaxLayoutWidth = contentWidth - 40
        intro.translatesAutoresizingMaskIntoConstraints = false
        intro.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        intro.maximumNumberOfLines = 0
        intro.lineBreakMode = .byWordWrapping

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        // Let the scroll area absorb vertical space between header and footer.
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        // Pin document view width to the clip view so rows align in one column.
        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: clip.widthAnchor)
        ])

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let rowSpacer = NSView()
        rowSpacer.translatesAutoresizingMaskIntoConstraints = false
        rowSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        buttonRow.addArrangedSubview(rowSpacer)
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(saveButton)

        root.addSubview(intro)
        root.addSubview(scrollView)
        root.addSubview(separator)
        root.addSubview(buttonRow)

        let scrollMinH = scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: minScrollAreaHeight)
        scrollMinH.priority = .required

        NSLayoutConstraint.activate([
            intro.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            intro.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            intro.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 12),
            scrollMinH,

            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),

            buttonRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            buttonRow.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

            root.widthAnchor.constraint(equalToConstant: contentWidth),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: minWindowContentHeight)
        ])

        buildRows()
        self.view = root
        preferredContentSize = NSSize(width: contentWidth, height: minWindowContentHeight)

        timerObserver = NotificationCenter.default.addObserver(
            forName: .laterSessionTimersChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // External edits (e.g. popover) — sync draft to disk state.
            self.draftSlots = SessionSlotStore.allSlots()
            self.refreshAllRows()
        }
    }

    deinit {
        if let o = timerObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        draftSlots = SessionSlotStore.allSlots()
        refreshAllRows()
        view.window?.delegate = self
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // After the view is in a window, enforce min size (see `applyWindowSizingHints`).
        applyWindowSizingHints()
    }

    /// Ensure the host window cannot collapse to a strip; `NSWindow` may size
    /// from ambiguous content before the first layout pass.
    private func applyWindowSizingHints() {
        guard let win = view.window else { return }
        // `contentMinSize` applies to the window content rect (below the title bar).
        win.contentMinSize = NSSize(width: contentWidth, height: minWindowContentHeight)
        // First layout can still leave a collapsed height before constraints solve; force a usable size.
        win.setContentSize(NSSize(width: contentWidth, height: minWindowContentHeight))
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelClicked()
        return false
    }

    // MARK: - Actions

    @objc private func saveClicked() {
        SessionTimerEditing.commitPlannerDraft(draftSlots)
        view.window?.orderOut(nil)
    }

    @objc private func cancelClicked() {
        draftSlots = SessionSlotStore.allSlots()
        view.window?.orderOut(nil)
    }

    // MARK: - Rows

    /// Width for wrapping status lines inside one grid cell (two columns in the scroll area).
    private var slotCardLabelPreferredMaxWidth: CGFloat {
        let scrollInset: CGFloat = 12 * 2
        let columnGap: CGFloat = 10
        let cardPaddingH: CGFloat = 12 * 2
        let inner = contentWidth - scrollInset
        return max(120, (inner - columnGap) / 2 - cardPaddingH)
    }

    private func buildRows() {
        rowPopups = []
        rowDetailLabels = []
        rowSaveDetailLabels = []
        saveRowPopups = []
        rowTitleLabels = []
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let labelMaxW = slotCardLabelPreferredMaxWidth

        for row in 0..<3 {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 12
            rowStack.distribution = .fillEqually
            rowStack.alignment = .top
            rowStack.translatesAutoresizingMaskIntoConstraints = false

            for col in 0..<2 {
                let i = row * 2 + col
                let card = buildSlotCard(slotIndex: i, labelMaxWidth: labelMaxW)
                rowStack.addArrangedSubview(card)
            }
            stack.addArrangedSubview(rowStack)
        }
    }

    private func buildSlotCard(slotIndex i: Int, labelMaxWidth: CGFloat) -> NSView {
        let slot = draftSlots[i]
        let titleStr: String
        if slot.hasSession {
            titleStr = "Slot \(i + 1) — \(slot.sessionName)"
        } else {
            titleStr = "Slot \(i + 1) — empty"
        }
        let title = NSTextField(labelWithString: titleStr)
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.cell?.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        rowTitleLabels.append(title)

        let reopenHeading = NSTextField(labelWithString: "Restore")
        reopenHeading.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        reopenHeading.textColor = .secondaryLabelColor
        reopenHeading.toolTip = "Runs Restore for this slot at the chosen time (after a delay or at clock time)."

        let detail = NSTextField(wrappingLabelWithString: SessionTimerEditing.summaryForPlannerDraft(slot: slot, slotIndex: i))
        detail.font = NSFont.systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = labelMaxWidth
        detail.translatesAutoresizingMaskIntoConstraints = false
        rowDetailLabels.append(detail)

        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.tag = i
        popUp.target = self
        popUp.action = #selector(plannerPopupChanged(_:))
        rebuildMenu(for: popUp, slotIndex: i)
        rowPopups.append(popUp)

        let saveHeading = NSTextField(labelWithString: "Scheduled save")
        saveHeading.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        saveHeading.textColor = .secondaryLabelColor
        saveHeading.toolTip = "Save windows for later into this slot at clock time (same as the green button)."

        let saveDetail = NSTextField(wrappingLabelWithString: SessionTimerEditing.saveScheduleSummaryForPlannerDraft(slot: slot, slotIndex: i))
        saveDetail.font = NSFont.systemFont(ofSize: 10)
        saveDetail.textColor = .secondaryLabelColor
        saveDetail.preferredMaxLayoutWidth = labelMaxWidth
        saveDetail.translatesAutoresizingMaskIntoConstraints = false
        rowSaveDetailLabels.append(saveDetail)

        let savePop = NSPopUpButton(frame: .zero, pullsDown: false)
        savePop.translatesAutoresizingMaskIntoConstraints = false
        savePop.tag = i
        savePop.target = self
        savePop.action = #selector(savePlannerPopupChanged(_:))
        rebuildSaveMenu(for: savePop, slotIndex: i)
        saveRowPopups.append(savePop)

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.spacing = 4
        inner.alignment = .width
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        inner.addArrangedSubview(title)
        inner.setCustomSpacing(6, after: title)
        inner.addArrangedSubview(reopenHeading)
        inner.addArrangedSubview(detail)
        inner.addArrangedSubview(popUp)
        inner.setCustomSpacing(10, after: popUp)
        inner.addArrangedSubview(saveHeading)
        inner.addArrangedSubview(saveDetail)
        inner.addArrangedSubview(savePop)

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return card
    }

    private enum PlannerMenuTag: Int {
        case off = 1
        case m15 = 15
        case m30 = 30
        case h1 = 60
        case h5 = 300
        case clock = 7713
    }

    private enum SavePlannerMenuTag: Int {
        case off = 1
        case clock = 7714
    }

    private func rebuildMenu(for popUp: NSPopUpButton, slotIndex: Int) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let slot = draftSlots[slotIndex]

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

    private func rebuildSaveMenu(for popUp: NSPopUpButton, slotIndex: Int) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let slot = draftSlots[slotIndex]

        func add(_ title: String, tag: Int) {
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            it.tag = tag
            menu.addItem(it)
        }

        add("Off", tag: SavePlannerMenuTag.off.rawValue)
        menu.addItem(NSMenuItem.separator())
        add("Clock time…", tag: SavePlannerMenuTag.clock.rawValue)

        popUp.menu = menu

        switch slot.saveScheduleMode {
        case .off:
            popUp.selectItem(withTag: SavePlannerMenuTag.off.rawValue)
        case .clockTime:
            popUp.selectItem(withTag: SavePlannerMenuTag.clock.rawValue)
        }
    }

    private func refreshAllRows() {
        guard rowPopups.count == SessionSlotStore.slotCount,
              rowDetailLabels.count == SessionSlotStore.slotCount,
              rowSaveDetailLabels.count == SessionSlotStore.slotCount,
              saveRowPopups.count == SessionSlotStore.slotCount,
              rowTitleLabels.count == SessionSlotStore.slotCount else { return }
        for i in 0..<SessionSlotStore.slotCount {
            let slot = draftSlots[i]
            if slot.hasSession {
                rowTitleLabels[i].stringValue = "Slot \(i + 1) — \(slot.sessionName)"
            } else {
                rowTitleLabels[i].stringValue = "Slot \(i + 1) — empty"
            }
            rowDetailLabels[i].stringValue = SessionTimerEditing.summaryForPlannerDraft(slot: slot, slotIndex: i)
            rowSaveDetailLabels[i].stringValue = SessionTimerEditing.saveScheduleSummaryForPlannerDraft(slot: slot, slotIndex: i)
            rebuildMenu(for: rowPopups[i], slotIndex: i)
            rebuildSaveMenu(for: saveRowPopups[i], slotIndex: i)
        }
    }

    @objc private func plannerPopupChanged(_ sender: NSPopUpButton) {
        let slotIndex = sender.tag
        guard slotIndex >= 0 && slotIndex < SessionSlotStore.slotCount,
              let item = sender.selectedItem else { return }
        let tag = item.tag

        switch tag {
        case PlannerMenuTag.off.rawValue:
            var s = draftSlots[slotIndex]
            s.reopenMode = .off
            draftSlots[slotIndex] = s
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.m15.rawValue:
            var s = draftSlots[slotIndex]
            s.reopenMode = .duration
            s.reopenDurationMinutes = 15
            draftSlots[slotIndex] = s
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.m30.rawValue:
            var s = draftSlots[slotIndex]
            s.reopenMode = .duration
            s.reopenDurationMinutes = 30
            draftSlots[slotIndex] = s
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.h1.rawValue:
            var s = draftSlots[slotIndex]
            s.reopenMode = .duration
            s.reopenDurationMinutes = 60
            draftSlots[slotIndex] = s
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.h5.rawValue:
            var s = draftSlots[slotIndex]
            s.reopenMode = .duration
            s.reopenDurationMinutes = 300
            draftSlots[slotIndex] = s
            refreshRowDetail(slotIndex: slotIndex)
        case PlannerMenuTag.clock.rawValue:
            presentClockEditor(slotIndex: slotIndex)
            rebuildMenu(for: sender, slotIndex: slotIndex)
        default:
            break
        }
    }

    @objc private func savePlannerPopupChanged(_ sender: NSPopUpButton) {
        let slotIndex = sender.tag
        guard slotIndex >= 0 && slotIndex < SessionSlotStore.slotCount,
              let item = sender.selectedItem else { return }
        let tag = item.tag

        switch tag {
        case SavePlannerMenuTag.off.rawValue:
            var s = draftSlots[slotIndex]
            s.saveScheduleMode = SessionSlotStore.SaveScheduleMode.off
            draftSlots[slotIndex] = s
            refreshRowSaveDetail(slotIndex: slotIndex)
        case SavePlannerMenuTag.clock.rawValue:
            presentSaveClockEditor(slotIndex: slotIndex)
            rebuildSaveMenu(for: sender, slotIndex: slotIndex)
        default:
            break
        }
    }

    private func refreshRowDetail(slotIndex: Int) {
        guard slotIndex < rowDetailLabels.count else { return }
        let slot = draftSlots[slotIndex]
        rowDetailLabels[slotIndex].stringValue = SessionTimerEditing.summaryForPlannerDraft(slot: slot, slotIndex: slotIndex)
    }

    private func refreshRowSaveDetail(slotIndex: Int) {
        guard slotIndex < rowSaveDetailLabels.count else { return }
        let slot = draftSlots[slotIndex]
        rowSaveDetailLabels[slotIndex].stringValue = SessionTimerEditing.saveScheduleSummaryForPlannerDraft(slot: slot, slotIndex: slotIndex)
    }

    private func presentClockEditor(slotIndex: Int) {
        if let w = saveClockSheetWindow, w.isVisible { w.close() }
        if let w = clockSheetWindow, w.isVisible {
            w.close()
        }
        let slot = draftSlots[slotIndex]
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
            guard let self else { return }
            var s = self.draftSlots[slotIndex]
            s.reopenMode = .clockTime
            s.reopenClockHour = max(0, min(23, hour))
            s.reopenClockMinute = max(0, min(59, minute))
            s.reopenWeekdays = weekdays.sorted()
            self.draftSlots[slotIndex] = s
            self.refreshRowDetail(slotIndex: slotIndex)
            if slotIndex < self.rowPopups.count {
                self.rebuildMenu(for: self.rowPopups[slotIndex], slotIndex: slotIndex)
            }
            self.clockSheetWindow = nil
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

    private func presentSaveClockEditor(slotIndex: Int) {
        if let w = clockSheetWindow, w.isVisible { w.close() }
        if let w = saveClockSheetWindow, w.isVisible { w.close() }
        let slot = draftSlots[slotIndex]
        let titleSuffix: String
        if slot.hasSession {
            titleSuffix = "Slot \(slotIndex + 1) — \(slot.sessionName)"
        } else {
            titleSuffix = "Slot \(slotIndex + 1) — empty"
        }
        let sheet = ClockTimeSheetController(
            initialHour: slot.saveClockHour,
            initialMinute: slot.saveClockMinute,
            initialWeekdays: Set(slot.saveWeekdays)
        )
        sheet.onConfirm = { [weak self] hour, minute, weekdays in
            guard let self else { return }
            var s = self.draftSlots[slotIndex]
            s.saveScheduleMode = SessionSlotStore.SaveScheduleMode.clockTime
            s.saveClockHour = max(0, min(23, hour))
            s.saveClockMinute = max(0, min(59, minute))
            s.saveWeekdays = weekdays.sorted()
            self.draftSlots[slotIndex] = s
            self.refreshRowSaveDetail(slotIndex: slotIndex)
            if slotIndex < self.saveRowPopups.count {
                self.rebuildSaveMenu(for: self.saveRowPopups[slotIndex], slotIndex: slotIndex)
            }
            self.saveClockSheetWindow = nil
        }
        sheet.onCancel = { [weak self] in
            self?.refreshAllRows()
            self?.saveClockSheetWindow = nil
        }
        sheet.onWindowClosed = { [weak self] in
            self?.saveClockSheetWindow = nil
        }
        let win = NSWindow(contentViewController: sheet)
        win.title = "Save schedule — \(titleSuffix)"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 400, height: 300))
        win.center()
        saveClockSheetWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
