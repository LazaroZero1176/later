//
//  ViewController.swift
//  Test
//
//  Created by Alyssa X on 1/22/22.
//

import Cocoa
import CoreGraphics
import LaunchAtLogin
import KeyboardShortcuts
@preconcurrency import ScreenCaptureKit

/// Borderless, layer-drawn button used for the Session slot grid.
/// Native `.rounded` bezel buttons render badly on the dark options box
/// (they lose their bezel when `wantsLayer` is enabled), so we draw our own.
///
/// v2.6.0 adds a per-slot reopen-timer indicator in the top-right corner
/// (see `setTimerArmed`): a small clock symbol for one-shot schedules and a
/// "repeat" symbol for recurring clock-time schedules. The badge is drawn
/// directly onto the button's layer so it redraws cheaply alongside the
/// existing color updates.
final class SlotButton: NSButton {

    enum ArmedKind: Equatable { case none, oneShot, recurring }

    private var isActiveSlot = false
    private var armedKind: ArmedKind = .none
    private let badgeLayer = CALayer()
    private let badgeImageLayer = CALayer()

    init(slotIndex: Int, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.tag = slotIndex
        self.title = "\(slotIndex + 1)"
        self.target = target
        self.action = action
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.focusRingType = .none
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Badge layer sits in the top-right corner. Hidden by default.
        badgeLayer.backgroundColor = NSColor(white: 0, alpha: 0.35).cgColor
        badgeLayer.cornerRadius = 7
        badgeLayer.isHidden = true
        badgeLayer.addSublayer(badgeImageLayer)
        badgeImageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(badgeLayer)

        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let badgeSize: CGFloat = 14
        let inset: CGFloat = 3
        let x = bounds.width - badgeSize - inset
        let y = bounds.height - badgeSize - inset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badgeLayer.frame = NSRect(x: x, y: y, width: badgeSize, height: badgeSize)
        badgeImageLayer.frame = badgeLayer.bounds.insetBy(dx: 2, dy: 2)
        CATransaction.commit()
    }

    func setActive(_ on: Bool) {
        guard isActiveSlot != on else { return }
        isActiveSlot = on
        applyColors()
    }

    /// Called by the per-second ticker in `ViewController`. Updates the
    /// visible badge and tooltip. Cheap no-op when nothing changed.
    func setTimerArmed(_ kind: ArmedKind, tooltip: String?) {
        self.toolTip = tooltip
        guard armedKind != kind else { return }
        armedKind = kind
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch kind {
        case .none:
            badgeLayer.isHidden = true
            badgeImageLayer.contents = nil
        case .oneShot, .recurring:
            badgeLayer.isHidden = false
            let symbolName = (kind == .recurring) ? "arrow.clockwise" : "clock"
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
                let cfg = img.withSymbolConfiguration(config) ?? img
                cfg.isTemplate = true
                badgeImageLayer.contents = tintedCGImage(for: cfg, tint: .white)
            }
        }
        CATransaction.commit()
    }

    private func tintedCGImage(for image: NSImage, tint: NSColor) -> CGImage? {
        let size = image.size == .zero ? NSSize(width: 12, height: 12) : image.size
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        rep?.size = size
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        tint.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private func applyColors() {
        let bg: NSColor = isActiveSlot
            ? NSColor.controlAccentColor
            : NSColor(white: 1.0, alpha: 0.08)
        let fg: NSColor = isActiveSlot
            ? .white
            : NSColor(white: 0.92, alpha: 1)
        layer?.backgroundColor = bg.cgColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: fg,
                .font: font ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
                .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()
            ]
        )
    }
}

class ViewController: NSViewController {

    @IBOutlet var currentView: NSView!
    @IBOutlet weak var preview: NSImageView!
    @IBOutlet weak var button: NSButton!
    @IBOutlet weak var restore: NSButton!
    @IBOutlet weak var box: NSBox!
    @IBOutlet weak var dateLabel: NSTextField!
    @IBOutlet weak var sessionLabel: NSTextField!
    @IBOutlet weak var numberOfSessions: NSButton!
    @IBOutlet weak var checkbox: NSButton!
    @IBOutlet weak var ignoreFinder: NSButton!
    @IBOutlet weak var keepWindowsOpen: NSButton!
    @IBOutlet weak var waitCheckbox: NSButton!
    @IBOutlet weak var timeDropdown: NSPopUpButton!
    @IBOutlet weak var timeLabel: NSTextField!
    @IBOutlet weak var cancelTime: NSButton!
    @IBOutlet weak var timeWrapper: NSView!
    @IBOutlet weak var timeWrapperHeight: NSLayoutConstraint!
    @IBOutlet weak var closeApps: NSButton!

    // v2.5.0 replaces the legacy "Disable all shortcuts" single toggle with
    // two entries: a "Configure shortcuts…" item that opens the recorder
    // sheet (ShortcutSettingsController) and a master on/off toggle that
    // enables or disables every recorded shortcut at once. The `switchKey`
    // UserDefaults key keeps its historical polarity (`true` = disabled) so
    // existing installs don't lose their choice across the upgrade.
    private let menuItemConfigureShortcuts = NSMenuItem(
        title: "Configure shortcuts…",
        action: #selector(openShortcutSettingsFromMenu(_:)),
        keyEquivalent: ""
    )
    private let menuItemEnableShortcuts = NSMenuItem(
        title: "Enable global shortcuts",
        action: #selector(toggleShortcutsEnabled(_:)),
        keyEquivalent: ""
    )

    private let menuItemShowDock = NSMenuItem(
        title: "Show Dock icon",
        action: #selector(toggleDockFromMenu(_:)),
        keyEquivalent: ""
    )
    private let menuItemShowMenuBar = NSMenuItem(
        title: "Show menu bar icon",
        action: #selector(toggleMenuBarFromMenu(_:)),
        keyEquivalent: ""
    )
    // Added in v2.4.1 so users on Tahoe can opt out of the Liquid Glass look.
    // Only inserted into the menu on macOS 26+ (see `setUpMenu`).
    private let menuItemLiquidGlass = NSMenuItem(
        title: "Use Liquid Glass (Tahoe)",
        action: #selector(toggleLiquidGlassFromMenu(_:)),
        keyEquivalent: ""
    )


    let settingsMenu = NSMenu()

    /// v2.6.0 — single UI ticker that refreshes the active slot's countdown
    /// label and every SlotButton's badge/tooltip once a second. Driven by
    /// `ReopenTimerManager.shared.fireDate(for:)`; the manager owns the
    /// actual restore timers. Nil when no slot is armed.
    private var uiTicker: Timer?

    /// Menu item identifier for the dynamic "At HH:MM [· weekdays]" entry we
    /// insert at the top of `timeDropdown` while the active slot is in
    /// clock-time mode. Using a tag lets us find / replace it without
    /// pattern-matching the title.
    private let clockDropdownItemTag = 7711

    /// Opens the central Time planner window (all six slots). Tag must stay
    /// in sync with `SessionTimePlannerController.PlannerMenuTag.clock`.
    private let timePlannerMenuTag = 7713
    private let timePlannerMenuTitle = "Time planner…"

    /// Gear menu — opens the same window as the popover dropdown entry.
    private let menuItemTimePlanner = NSMenuItem(
        title: "Time planner…",
        action: #selector(openTimePlannerFromGear(_:)),
        keyEquivalent: ""
    )

    private var sessionTimerObserver: NSObjectProtocol?

    @IBOutlet weak var boxHeight: NSLayoutConstraint!
    @IBOutlet weak var topBoxSpacing: NSLayoutConstraint!
    // Previously drove the popover height as a fixed constant; replaced by
    // content-driven layout (button bottom → view bottom). Kept optional so
    // the outlet-free storyboard load does not crash during transition.
    @IBOutlet weak var containerHeight: NSLayoutConstraint?
    @IBOutlet weak var optionsBox: NSBox!
    @IBOutlet weak var saveBelowOptionsConstraint: NSLayoutConstraint!

    private var excludeSetupStack: NSStackView?
    private let excludeSetupPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private weak var excludeSetupEditorWindow: NSWindow?

    /// Clock-time + weekday editor must not use `presentAsSheet` — that API is
    /// unreliable when this `ViewController` lives inside an `NSPopover` (the
    /// sheet often never appears). We host `ClockTimeSheetController` in a
    /// plain titled window instead, matching `ExcludeSetupEditorController`.
    private var clockTimeSheetWindow: NSWindow?

    /// Session slots (1–6) sit inside the options box under the last setting row.
    private var sessionSlotsRoot: NSStackView?
    private var sessionSlotButtons: [NSButton] = []

    /// Placeholder shown in the session preview box when the active slot is empty.
    private var noSessionLabel: NSTextField?

    let defaults = UserDefaults.standard

    var observers = [NSKeyValueObservation]()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Run all storage migrations *before* we start reading values back:
        // `refreshUIForActiveSlot()` below calls `syncExcludeSetupPopUp()`
        // which expects up-to-date display names and per-slot modes.
        SessionSlotStore.migrateIfNeeded()
        ExcludeSetupStore.migrateIfNeeded()
        migrateShortcutsV2IfNeeded()

        checkbox.state = LaunchAtLogin.isEnabled ? .on : .off
        closeApps.state = defaults.bool(forKey: "closeApps") ? .on : .off
        ignoreFinder.state = defaults.bool(forKey: "ignoreSystem") ? .on : .off
        keepWindowsOpen.state = defaults.bool(forKey: "keepWindowsOpen") ? .on : .off
        // v2.6.0: the "Reopen this session" checkbox + the time dropdown are
        // per-slot, driven by SessionSlotStore.Slot.reopenMode. See
        // `refreshUIForActiveSlot()` for the binding logic.
        timeDropdown.target = self
        timeDropdown.action = #selector(timeDropdownChanged(_:))

        // Reflect the master on/off state in the gear menu checkmark.
        // `switchKey == true` means shortcuts are disabled, so the
        // "Enable global shortcuts" item should appear unchecked.
        menuItemEnableShortcuts.state = defaults.bool(forKey: "switchKey") ? .off : .on

        buildSessionSlotSectionIfNeeded()
        buildExcludeSetupRowIfNeeded()
        buildNoSessionPlaceholderIfNeeded()
        refreshUIForActiveSlot()

        setUpMenu()
        observeModel()

        sessionTimerObserver = NotificationCenter.default.addObserver(
            forName: .laterSessionTimersChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshUIForActiveSlot()
            self.refreshSlotBadges()
            self.startUiTickerIfNeeded()
            self.updateTimeLabelForActiveSlot()
        }

        syncExcludeSetupPopUp()
        applyLiquidGlassIfAvailable()
    }

    deinit {
        if let o = sessionTimerObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    /// On macOS 26 (Tahoe) and later, the popover can render with a Liquid
    /// Glass material. The pre-existing dark-tinted NSBoxes (`box` for the
    /// session preview, `optionsBox` for the options row) would cover that
    /// material with opaque fills, so we make them transparent on Tahoe+ and
    /// let the popover's backdrop show through — unless the user disabled
    /// Liquid Glass from the gear menu, in which case we restore the legacy
    /// dark fill byte-identical to the storyboard default.
    /// Pre-Tahoe systems always keep the legacy look.
    private func applyLiquidGlassIfAvailable() {
        guard #available(macOS 26.0, *) else { return }
        if isLiquidGlassEnabled {
            box.fillColor = .clear
            optionsBox.fillColor = .clear
        } else {
            box.fillColor = Self.legacyBoxFillColor
            optionsBox.fillColor = Self.legacyBoxFillColor
        }
    }

    /// Matches the `fillColor` set on both `NSBox`es in `Main.storyboard`
    /// (IDs `MPy-SW-b88` / `9VD-Ls-6F0`). Keep in sync if the storyboard ever
    /// changes — it is the visual fallback when a user disables Liquid Glass.
    private static let legacyBoxFillColor = NSColor(
        displayP3Red: 0.184316784,
        green: 0.184308290,
        blue: 0.184314042,
        alpha: 1
    )

    /// True when the Tahoe Liquid Glass look should be used. Always false on
    /// pre-Tahoe because the material isn't available there anyway.
    private var isLiquidGlassEnabled: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return defaults.object(forKey: "useLiquidGlass") as? Bool ?? true
    }

    @objc private func toggleLiquidGlassFromMenu(_ sender: NSMenuItem) {
        guard #available(macOS 26.0, *) else { return }
        let current = defaults.object(forKey: "useLiquidGlass") as? Bool ?? true
        let next = !current
        defaults.set(next, forKey: "useLiquidGlass")
        sender.state = next ? .on : .off
        // Re-apply immediately so a user toggling while the popover is open
        // sees the change without having to close and reopen it.
        applyLiquidGlassIfAvailable()
        applyExcludeSetupRowStyle()
        (NSApp.delegate as? AppDelegate)?.reapplyPopoverAppearance()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updatePreferredContentSize()
        // Make sure the dropdown and countdown reflect the live state each
        // time the popover is shown — timers may have fired while closed.
        refreshUIForActiveSlot()
        startUiTickerIfNeeded()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        // No need to keep the 1s UI ticker alive while the popover is gone;
        // the manager owns the actual restore timers.
        stopUiTicker()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    private func presentBothOffAlert() {
        let alert = NSAlert()
        alert.messageText = "Later needs a visible entry point"
        alert.informativeText = "Leave at least one of the Dock icon or the menu bar icon enabled. Otherwise you can only open Later with the global keyboard shortcuts (unless those are disabled below)."
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func syncAppearanceMenuItemsFromDefaults() {
        menuItemShowDock.state = (defaults.object(forKey: "showDockIcon") as? Bool ?? true) ? .on : .off
        menuItemShowMenuBar.state = (defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true) ? .on : .off
        menuItemLiquidGlass.state = (defaults.object(forKey: "useLiquidGlass") as? Bool ?? true) ? .on : .off
    }

    @objc private func toggleDockFromMenu(_ sender: NSMenuItem) {
        let showDock = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        let showMenu = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        let newDock = !showDock
        if !newDock && !showMenu {
            presentBothOffAlert()
            return
        }
        defaults.set(newDock, forKey: "showDockIcon")
        sender.state = newDock ? .on : .off
        NotificationCenter.default.post(name: .laterAppearanceChanged, object: nil)
    }

    @objc private func toggleMenuBarFromMenu(_ sender: NSMenuItem) {
        let showDock = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        let showMenu = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        let newMenu = !showMenu
        if !showDock && !newMenu {
            presentBothOffAlert()
            return
        }
        defaults.set(newMenu, forKey: "showMenuBarIcon")
        sender.state = newMenu ? .on : .off
        NotificationCenter.default.post(name: .laterAppearanceChanged, object: nil)
    }

    func observeModel() {
        self.observers = [
            NSWorkspace.shared.observe(\.runningApplications, options: [.initial]) { [weak self] _, _ in
                Task { @MainActor in self?.checkAnyWindows() }
            }
        ]
    }

    // MARK: - Timer UI ticker (v2.6.0)
    //
    // The actual per-slot restore timers live in `ReopenTimerManager`. This
    // ticker only drives the visible countdown on the active slot's
    // `timeLabel` plus every SlotButton's badge / tooltip. We start it when
    // at least one slot is armed and stop it when all slots are quiet, so
    // the popover does no wake-ups at rest.

    private func startUiTickerIfNeeded() {
        guard uiTicker == nil else { return }
        guard anySlotArmed() else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickUI()
        }
        RunLoop.main.add(t, forMode: .common)
        uiTicker = t
        tickUI()
    }

    private func stopUiTicker() {
        uiTicker?.invalidate()
        uiTicker = nil
    }

    private func anySlotArmed() -> Bool {
        for i in 0..<SessionSlotStore.slotCount {
            if ReopenTimerManager.shared.fireDate(for: i) != nil { return true }
        }
        return false
    }

    private func tickUI() {
        refreshSlotBadges()
        updateTimeLabelForActiveSlot()
        if !anySlotArmed() {
            stopUiTicker()
        }
    }

    private func refreshSlotBadges() {
        let mgr = ReopenTimerManager.shared
        for btn in sessionSlotButtons {
            guard let sb = btn as? SlotButton else { continue }
            let idx = sb.tag
            if mgr.fireDate(for: idx) != nil {
                let kind: SlotButton.ArmedKind = mgr.isRecurring(slotIndex: idx) ? .recurring : .oneShot
                sb.setTimerArmed(kind, tooltip: slotTooltip(for: idx))
            } else {
                sb.setTimerArmed(.none, tooltip: nil)
            }
        }
    }

    private func slotTooltip(for slotIndex: Int) -> String? {
        let slot = SessionSlotStore.slot(at: slotIndex)
        let mgr = ReopenTimerManager.shared
        guard let fire = mgr.fireDate(for: slotIndex) else { return nil }
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        let hhmm = df.string(from: fire)
        switch slot.activeReopenPolicy {
        case .off:
            return nil
        case .duration:
            return mgr.remainingString(for: slotIndex)
        case .clockTime(_, _, let weekdays):
            if weekdays.isEmpty {
                return "Reopens at \(hhmm)"
            }
            return "Repeats \(weekdayListString(weekdays)) · next \(hhmm)"
        }
    }

    private func updateTimeLabelForActiveSlot() {
        let idx = SessionSlotStore.activeIndex()
        let mgr = ReopenTimerManager.shared
        guard let fire = mgr.fireDate(for: idx) else {
            hideTimer()
            return
        }
        let slot = SessionSlotStore.slot(at: idx)
        showTimer()
        switch slot.activeReopenPolicy {
        case .off:
            hideTimer()
        case .duration:
            timeLabel.stringValue = mgr.remainingString(for: idx) ?? ""
        case .clockTime(_, _, let weekdays):
            let df = DateFormatter()
            df.timeStyle = .short
            df.dateStyle = .none
            let hhmm = df.string(from: fire)
            if weekdays.isEmpty {
                timeLabel.stringValue = "Reopens at \(hhmm)"
            } else {
                timeLabel.stringValue = "Repeats \(weekdayListString(weekdays)) · next \(hhmm)"
            }
        }
    }

    /// Compact, locale-independent weekday list — "Mon, Tue, Thu" or "Daily"
    /// when all seven days are selected. Sort order is Mon first (ISO-ish),
    /// which reads more naturally in the tooltip than `Calendar`'s default
    /// (Sun=1).
    private func weekdayListString(_ weekdays: Set<Int>) -> String {
        if weekdays.count == 7 { return "Daily" }
        let order = [2, 3, 4, 5, 6, 7, 1]   // Mon ... Sat, then Sun
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return order
            .filter { weekdays.contains($0) }
            .compactMap { (1...7).contains($0) ? names[$0] : nil }
            .joined(separator: ", ")
    }

    // MARK: - App filtering helpers

    /// Identify Apple-supplied utility apps by bundle identifier (locale-independent).
    /// Replaces the brittle hardcoded English name list (ISSUE-07, ISSUE-19).
    private static let systemBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.ActivityMonitor",
        "com.apple.systempreferences",     // macOS <= 12
        "com.apple.systemsettings",        // macOS 13+
        "com.apple.AppStore"
    ]

    private func isSystemApp(_ app: NSRunningApplication) -> Bool {
        if let bid = app.bundleIdentifier, Self.systemBundleIDs.contains(bid) { return true }
        return false
    }

    private func isSelf(_ app: NSRunningApplication) -> Bool {
        return app.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Should this running application be treated as part of a "session"?
    private func shouldInclude(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        if isSelf(app) { return false }
        if ignoreFinder.state == .on && isSystemApp(app) { return false }
        let mode = ExcludeSetupStore.mode(forSessionSlot: SessionSlotStore.activeIndex())
        let excluded = ExcludeSetupStore.excludedBundleIDs(for: mode)
        if let bid = app.bundleIdentifier, excluded.contains(bid) { return false }
        return true
    }

    func checkAnyWindows() {
        let total = NSWorkspace.shared.runningApplications.reduce(into: 0) { acc, app in
            if shouldInclude(app) { acc += 1 }
        }
        button.isEnabled = total > 0
    }

    // MARK: - Menu actions

    @objc func openURL() {
        guard let url = URL(string: "https://github.com/LazaroZero1176/later") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func checkForUpdates() {
        // Use Sparkle to check for updates, not relevant in this version.
    }

    /// Open the modeless shortcut settings window hosted by `AppDelegate`.
    /// The gear menu's "Configure shortcuts…" item routes here.
    @objc func openShortcutSettingsFromMenu(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openShortcutSettings(sender)
    }

    /// Toggle the master "Enable global shortcuts" flag and ask
    /// `AppDelegate` to enable or disable every named shortcut in bulk.
    /// Keeps writing to the legacy `switchKey` key (polarity: `true` =
    /// disabled) so an upgrade round-trip is lossless.
    @objc func toggleShortcutsEnabled(_ sender: Any?) {
        let wasEnabled = menuItemEnableShortcuts.state == .on
        let enabledNow = !wasEnabled
        menuItemEnableShortcuts.state = enabledNow ? .on : .off
        defaults.set(!enabledNow, forKey: "switchKey")
        (NSApp.delegate as? AppDelegate)?.applyShortcutMasterToggle()
    }

    /// One-time migration for the v2.5.0 shortcuts rework.
    ///
    /// Historically `switchKey == true` meant "all shortcuts disabled" and
    /// the keys were hardcoded `⌘⇧L` / `⌘⇧R`. With `KeyboardShortcuts`
    /// taking over, defaults are seeded once by the package itself, but the
    /// legacy value of `switchKey` should still drive the enable/disable
    /// state — so we only need to *mark* the migration as done, no value
    /// flip required. The explicit flag lets us extend this later without
    /// rerunning against users who already upgraded.
    private func migrateShortcutsV2IfNeeded() {
        let key = "shortcutsV2Migrated"
        guard defaults.bool(forKey: key) == false else { return }
        defaults.set(true, forKey: key)
    }

    func setUpMenu() {
        menuItemShowDock.target = self
        menuItemShowMenuBar.target = self
        menuItemLiquidGlass.target = self
        menuItemConfigureShortcuts.target = self
        menuItemEnableShortcuts.target = self
        menuItemTimePlanner.target = self

        self.settingsMenu.addItem(NSMenuItem(title: "Visit website", action: #selector(openURL), keyEquivalent: ""))
        self.settingsMenu.addItem(menuItemConfigureShortcuts)
        self.settingsMenu.addItem(menuItemEnableShortcuts)
        self.settingsMenu.addItem(menuItemTimePlanner)
        self.settingsMenu.addItem(NSMenuItem.separator())
        self.settingsMenu.addItem(menuItemShowDock)
        self.settingsMenu.addItem(menuItemShowMenuBar)
        // Liquid Glass is a Tahoe-only feature; hide the opt-out toggle on
        // older macOS where the popover can't render with the new material.
        if #available(macOS 26.0, *) {
            self.settingsMenu.addItem(menuItemLiquidGlass)
        }
        self.settingsMenu.addItem(NSMenuItem.separator())
        // Lowercase "q" so Cmd+Q works without Shift (ISSUE-13).
        self.settingsMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        settingsMenu.appearance = NSAppearance.currentDrawing()
    }

    // MARK: - Screenshot storage

    /// Returns `~/Library/Application Support/Later/` creating it on demand (SEC-04).
    private static func appSupportDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let bundleID = Bundle.main.bundleIdentifier ?? "Later"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("Later: cannot create app support dir: \(error)")
            return nil
        }
        return dir
    }

    func setScreenshot() {
        let idx = SessionSlotStore.activeIndex()
        guard let fileUrl = SessionSlotStore.screenshotURL(for: idx) else {
            preview.image = nil
            return
        }
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            preview.image = NSImage(byReferencing: fileUrl)
        } else {
            preview.image = nil
        }
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 10
    }

    // MARK: - Screenshot capture

    /// Take a small preview screenshot. Uses ScreenCaptureKit on macOS 14+,
    /// falls back to legacy CGWindowListCreateImage otherwise (ISSUE-02).
    /// Silently no-ops on failure; the preview is non-essential.
    ///
    /// Always resolves Screen Recording permission via `CGPreflight` / `CGRequest`
    /// **before** calling ScreenCaptureKit. Hitting `SCShareableContent` without
    /// permission can make macOS show the “Screen Recording” dialog on every save.
    func takeScreenshot() {
        if #available(macOS 10.15, *) {
            if !CGPreflightScreenCaptureAccess() {
                guard CGRequestScreenCaptureAccess() else {
                    NSLog("Later: screenshot skipped — Screen Recording not granted (System Settings → Privacy & Security → Screen Recording)")
                    return
                }
            }
        }
        let slotIdx = SessionSlotStore.activeIndex()
        if #available(macOS 14.0, *) {
            Task.detached(priority: .userInitiated) {
                await Self.captureViaScreenCaptureKit(slotIndex: slotIdx)
            }
        } else {
            captureLegacy(slotIndex: slotIdx)
        }
    }

    @available(macOS 14.0, *)
    private static func captureViaScreenCaptureKit(slotIndex: Int) async {
        guard CGPreflightScreenCaptureAccess() else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let url = SessionSlotStore.screenshotURL(for: slotIndex) else { return }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }
            try data.write(to: url, options: .atomic)
        } catch {
            // Likely the user has not granted Screen Recording permission yet.
            NSLog("Later: screenshot failed: \(error.localizedDescription)")
        }
    }

    private func captureLegacy(slotIndex: Int) {
        guard let url = SessionSlotStore.screenshotURL(for: slotIndex) else { return }
        guard let image = CGWindowListCreateImage(.zero, .optionOnScreenOnly, kCGNullWindowID, [.nominalResolution]) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Later: cannot write screenshot: \(error)")
        }
    }

    // MARK: - Utility

    private static func makeCurrentDateString() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .medium
        return formatter.string(from: Date())
    }

    // MARK: - Styling fixes / overrides

    func fixStyles() {
        button.wantsLayer = true
        button.image = NSImage(named: "blue-button")
        button.imageScaling = .scaleAxesIndependently
        button.layer?.cornerRadius = 10

        restore.wantsLayer = true
        restore.image = NSImage(named: "green-button")
        restore.imageScaling = .scaleAxesIndependently
        restore.layer?.cornerRadius = 10

        numberOfSessions.wantsLayer = true
        numberOfSessions.layer?.backgroundColor = #colorLiteral(red: 0.9236671925, green: 0.1403781176, blue: 0.3365081847, alpha: 1)
        numberOfSessions.layer?.cornerRadius = numberOfSessions.frame.width / 2
        numberOfSessions.layer?.masksToBounds = true

        if let mutableAttributedTitle = numberOfSessions.attributedTitle.mutableCopy() as? NSMutableAttributedString {
            mutableAttributedTitle.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: mutableAttributedTitle.length))
            numberOfSessions.attributedTitle = mutableAttributedTitle
        }

        let checkboxes: [NSButton] = [checkbox, closeApps, ignoreFinder, keepWindowsOpen, waitCheckbox]
        let label = #colorLiteral(red: 0.9136554599, green: 0.9137651324, blue: 0.9136180282, alpha: 1)
        for cb in checkboxes {
            cb.image?.size = NSSize(width: 16, height: 16)
            cb.alternateImage?.size = NSSize(width: 16, height: 16)
            if let t = cb.attributedTitle.mutableCopy() as? NSMutableAttributedString {
                t.addAttribute(.foregroundColor, value: label, range: NSRange(location: 0, length: t.length))
                cb.attributedTitle = t
            }
        }

        timeDropdown.appearance = NSAppearance.currentDrawing()

        if let t = cancelTime.attributedTitle.mutableCopy() as? NSMutableAttributedString {
            t.addAttribute(.foregroundColor, value: #colorLiteral(red: 0.155318439, green: 0.5206356049, blue: 1, alpha: 1), range: NSRange(location: 0, length: t.length))
            cancelTime.attributedTitle = t
        }

        applyExcludeSetupRowStyle()
        applySessionSlotSectionStyle()
        updateSlotButtonHighlights()
    }

    // MARK: - IBActions

    @IBAction func startAtLogin(_ sender: Any) {
        LaunchAtLogin.isEnabled = (checkbox.state == .on)
    }

    @IBAction func closeAppsCheck(_ sender: Any) {
        defaults.set(closeApps.state == .on, forKey: "closeApps")
    }

    @IBAction func ignoreSystemWindows(_ sender: Any) {
        defaults.set(ignoreFinder.state == .on, forKey: "ignoreSystem")
    }

    @IBAction func keepWindowsOpen(_ sender: Any) {
        defaults.set(keepWindowsOpen.state == .on, forKey: "keepWindowsOpen")
    }

    @IBAction func waitCheckboxChange(_ sender: Any) {
        let on = waitCheckbox.state == .on
        let idx = SessionSlotStore.activeIndex()
        var slot = SessionSlotStore.slot(at: idx)
        if on {
            // Switch into the mode the dropdown's current selection implies
            // (duration vs clock-time). Default to duration when the dropdown
            // still shows a plain duration item.
            if slot.reopenMode == .off {
                slot.reopenMode = .duration
            }
            SessionSlotStore.setSlot(at: idx, slot)
            // Arm immediately only for recurring clock-time schedules — those
            // are autonomous (no Save needed). Duration and one-shot clock
            // remain save-triggered.
            if case .clockTime(_, _, let wd) = slot.activeReopenPolicy,
               !wd.isEmpty, slot.hasSession {
                ReopenTimerManager.shared.schedule(slotIndex: idx, policy: slot.activeReopenPolicy)
            }
        } else {
            SessionTimerEditing.applyOff(slotIndex: idx)
        }
        rebuildTimeDropdownForActiveSlot()
        refreshSlotBadges()
        startUiTickerIfNeeded()
    }

    @objc private func openTimePlannerFromGear(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openTimePlanner(sender)
    }

    /// Fired when the user picks one of the `timeDropdown` entries. We drive
    /// the active slot's `reopenMode` / `reopenDurationMinutes` /
    /// `reopenClock*` fields from the selection. "Time planner…" opens the
    /// central window for all six slots; the dynamic clock header re-opens the
    /// clock editor for the active slot only.
    @IBAction func timeDropdownChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        // The dynamic "At HH:MM" header (clockDropdownItemTag) simply
        // re-opens the editor so the user can adjust the schedule.
        if item.tag == clockDropdownItemTag {
            presentClockTimeSheet()
            return
        }
        if item.tag == timePlannerMenuTag {
            (NSApp.delegate as? AppDelegate)?.openTimePlanner(nil)
            rebuildTimeDropdownForActiveSlot()
            return
        }
        // Duration choices — menu item actions must be nil so only the
        // NSPopUpButton's action fires (AppKit).
        let minutes: Int?
        switch item.title {
        case "15 minutes": minutes = 15
        case "30 minutes": minutes = 30
        case "1 hour":     minutes = 60
        case "5 hours":    minutes = 300
        default: minutes = nil
        }
        guard let mins = minutes else { return }
        let idx = SessionSlotStore.activeIndex()
        SessionTimerEditing.applyDuration(slotIndex: idx, minutes: mins)
    }

    @IBAction func click(_ sender: Any) {
        saveSessionGlobal()
        button.isEnabled = false
    }

    @IBAction func imageClick(_ sender: Any) {
        restoreSessionGlobal()
    }

    @IBAction func restoreSession(_ sender: Any) {
        restoreSessionGlobal()
    }

    @IBAction func hideBox(_ sender: Any) {
        noSessions()
    }

    @IBAction func settings(_ sender: NSButton) {
        syncAppearanceMenuItemsFromDefaults()
        let p = NSPoint(x: sender.frame.origin.x, y: sender.frame.origin.y - (sender.frame.height / 2))
        settingsMenu.popUp(positioning: nil, at: p, in: sender.superview)
    }

    @IBAction func cancelTimeClick(_ sender: Any) {
        ReopenTimerManager.shared.cancel(slotIndex: SessionSlotStore.activeIndex())
        hideTimer()
        refreshSlotBadges()
    }

    // MARK: - Layout helpers

    func hideTimer() {
        timeWrapperHeight.constant = 0
        boxHeight.constant = 206
        timeWrapper.isHidden = true
        currentView.needsLayout = true
        currentView.updateConstraints()
    }

    func showTimer() {
        timeWrapperHeight.constant = 40
        boxHeight.constant = 226
        timeWrapper.isHidden = false
        currentView.needsLayout = true
        currentView.updateConstraints()
    }

    // MARK: - Save session

    func saveSessionGlobal() {
        var bundleIDs = [String]()
        var legacyURLs = [String]()
        var arrayNames = [String]()
        var sessionName = ""
        var sessionFull = ""
        var sessionsAdded = 1
        var sessionsRemaining = 0
        var totalSessions = 0
        var lastState = false

        takeScreenshot()

        let frontmost = NSWorkspace.shared.frontmostApplication

        // Remember the current activation policy so we can restore it at the
        // end of the save flow (see ISSUE-23). We used to blindly set
        // `.accessory` afterwards, which destroyed the Dock icon we rely on
        // as a visibility fallback.
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        func record(_ app: NSRunningApplication) {
            let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
            if let bid = app.bundleIdentifier {
                bundleIDs.append(bid)
            } else {
                bundleIDs.append("")
            }
            if let exec = app.executableURL?.absoluteString {
                legacyURLs.append(exec)
            } else {
                legacyURLs.append("")
            }
            arrayNames.append(name)

            if keepWindowsOpen.state == .off {
                let ok = app.hide()
                NSLog("Later: hide(\(name)) → \(ok ? "ok" : "ignored by target app")")
            } else {
                // Don't terminate system apps (Finder et al.) even if user enabled "keep windows open".
                if !isSystemApp(app) {
                    let ok = app.terminate()
                    NSLog("Later: terminate(\(name)) → \(ok ? "sent" : "refused")")
                }
                lastState = true
            }

            if sessionName.isEmpty {
                sessionName = name
                sessionFull = name
            } else if sessionsAdded <= 3 {
                sessionName += ", " + name
            } else {
                sessionsRemaining += 1
            }
            if !sessionFull.isEmpty { sessionFull += ", " }
            sessionFull += name
            sessionsAdded += 1
            totalSessions += 1
        }

        for app in NSWorkspace.shared.runningApplications where shouldInclude(app) {
            if app == frontmost { continue } // handled below
            record(app)
        }
        if let front = frontmost, shouldInclude(front) {
            record(front)
        }

        if sessionsRemaining > 0 {
            sessionName += ", +\(sessionsRemaining) more"
        }

        // Restore the activation policy the app had before we started saving.
        // In the current build this keeps `.regular` so the Dock icon stays
        // visible (ISSUE-23). If anyone ever switches the app back to
        // `.accessory` as the default, this will still behave correctly.
        NSApp.setActivationPolicy(previousPolicy)

        let dateStr = Self.makeCurrentDateString()
        let slot = SessionSlotStore.Slot(
            hasSession: true,
            lastState: lastState,
            date: dateStr,
            sessionName: sessionName,
            sessionFullName: sessionFull,
            totalSessions: String(totalSessions),
            appsLegacy: legacyURLs,
            appNames: arrayNames,
            appBundleIDs: bundleIDs
        )
        let activeIdx = SessionSlotStore.activeIndex()
        // Preserve the active slot's reopen config across the save (the
        // Slot struct we just built uses default timer fields). Pull the
        // existing settings, then overwrite everything else.
        let previous = SessionSlotStore.slot(at: activeIdx)
        var merged = slot
        merged.reopenMode             = previous.reopenMode
        merged.reopenDurationMinutes  = previous.reopenDurationMinutes
        merged.reopenClockHour        = previous.reopenClockHour
        merged.reopenClockMinute      = previous.reopenClockMinute
        merged.reopenWeekdays         = previous.reopenWeekdays
        merged.saveScheduleMode       = previous.saveScheduleMode
        merged.saveClockHour          = previous.saveClockHour
        merged.saveClockMinute        = previous.saveClockMinute
        merged.saveWeekdays           = previous.saveWeekdays
        SessionSlotStore.setSlot(at: activeIdx, merged)

        // Delegate timer arming to the manager. Off → no-op, duration →
        // now + N, clock-time → next matching HH:MM (optionally filtered by
        // weekdays). Recurring schedules keep rearming themselves in the
        // manager's fire handler.
        ReopenTimerManager.shared.schedule(slotIndex: activeIdx, policy: merged.activeReopenPolicy)

        refreshUIForActiveSlot()
        startUiTickerIfNeeded()

        (NSApp.delegate as? AppDelegate)?.closePopover(self)
    }

    // MARK: - Restore session

    /// Reopen an app, preferring a bundle identifier lookup via LaunchServices (ISSUE-11, SEC-05).
    /// Falls back to legacy executable URL only if that fails.
    private func activate(name: String, bundleID: String?, legacyURL: String?) {
        // Already running → just unhide. `app.terminate()` is async and a
        // just-terminated app can linger in `runningApplications` with
        // `isTerminated == true` for a short window; we must ignore those
        // zombies, otherwise the launch branch below is skipped and the app
        // stays gone (regression fixed in v2.3.1).
        if let bid = bundleID, !bid.isEmpty,
           let running = NSRunningApplication
               .runningApplications(withBundleIdentifier: bid)
               .first(where: { !$0.isTerminated }) {
            running.unhide()
            return
        }
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == name && !$0.isTerminated }) {
            running.unhide()
            return
        }

        // Launch via NSWorkspace.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false

        if let bid = bundleID, !bid.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, err in
                if let err { NSLog("Later: openApplication(\(bid)) failed: \(err)") }
            }
            return
        }

        // Legacy fallback: the stored URL is an *executable* URL inside an .app bundle.
        // Walk up to find the bundle root and open that via LaunchServices.
        if let raw = legacyURL, let execURL = URL(string: raw) {
            var url = execURL
            while url.pathExtension != "app" && url.path != "/" {
                url.deleteLastPathComponent()
            }
            if url.pathExtension == "app" {
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, err in
                    if let err { NSLog("Later: openApplication(url) failed: \(err)") }
                }
            }
        }
    }

    @objc func restoreSessionGlobal() {
        let stored = SessionSlotStore.slot(at: SessionSlotStore.activeIndex())
        guard stored.hasSession else {
            // Empty slot — nothing to restore. Beep so the user notices and
            // make sure we don't run the close-others loop against thin air.
            NSSound.beep()
            return
        }

        // Build a target set so the "close others" path can leave the
        // session's own apps untouched (no restart flicker) and so we have
        // a name-based fallback for legacy slots without bundle IDs.
        let targetBundleIDs = Set(stored.appBundleIDs.filter { !$0.isEmpty })
        let targetNames = Set(stored.appNames)

        if closeApps.state == .on {
            for app in NSWorkspace.shared.runningApplications where shouldInclude(app) {
                if app.bundleIdentifier == "com.apple.Terminal" { continue }
                if let bid = app.bundleIdentifier, targetBundleIDs.contains(bid) { continue }
                if let name = app.localizedName, targetNames.contains(name) { continue }
                app.terminate()
            }
        }

        let names = stored.appNames
        let bundleIDs = stored.appBundleIDs
        let legacyURLs = stored.appsLegacy

        let count = names.count
        for i in 0..<count {
            let name = names[i]
            let bid = i < bundleIDs.count ? bundleIDs[i] : nil
            let url = i < legacyURLs.count ? legacyURLs[i] : nil
            activate(name: name, bundleID: bid, legacyURL: url)
        }

        // Restore is now idempotent: the slot stays populated so it can be
        // re-applied any time as a preset. Use the X ("hideBox") control to
        // explicitly forget a slot.
        refreshUIForActiveSlot()

        (NSApp.delegate as? AppDelegate)?.closePopover(self)
    }

    // MARK: - Popover states

    func noSessions() {
        let idx = SessionSlotStore.activeIndex()
        // Keep the slot's reopen config — the user explicitly wiped the
        // session contents, not the schedule. Refilling this slot later
        // will auto-rearm recurring schedules (see `saveSessionGlobal`).
        let existing = SessionSlotStore.slot(at: idx)
        var cleared = SessionSlotStore.Slot.empty
        cleared.reopenMode            = existing.reopenMode
        cleared.reopenDurationMinutes = existing.reopenDurationMinutes
        cleared.reopenClockHour       = existing.reopenClockHour
        cleared.reopenClockMinute     = existing.reopenClockMinute
        cleared.reopenWeekdays        = existing.reopenWeekdays
        cleared.saveScheduleMode      = existing.saveScheduleMode
        cleared.saveClockHour         = existing.saveClockHour
        cleared.saveClockMinute       = existing.saveClockMinute
        cleared.saveWeekdays          = existing.saveWeekdays
        SessionSlotStore.setSlot(at: idx, cleared)
        ReopenTimerManager.shared.cancel(slotIndex: idx)
        applyEmptySlotUIOnly()
        updateSlotButtonHighlights()
        refreshSlotBadges()
    }

    /// Reloads labels, preview, and layout from the active session slot.
    private func refreshUIForActiveSlot() {
        let slot = SessionSlotStore.slot(at: SessionSlotStore.activeIndex())
        // Bind the per-slot timer UI *before* session-dependent sections so
        // the dropdown and checkbox reflect the freshly activated slot even
        // when it has no saved session.
        waitCheckbox.state = (slot.reopenMode == .off) ? .off : .on
        rebuildTimeDropdownForActiveSlot()

        if slot.hasSession {
            setSessionBoxPlaceholderVisible(false)
            dateLabel.stringValue = slot.date
            dateLabel.lineBreakMode = .byTruncatingTail
            sessionLabel.stringValue = slot.sessionName
            sessionLabel.lineBreakMode = .byTruncatingTail
            sessionLabel.toolTip = slot.sessionFullName
            numberOfSessions.title = slot.totalSessions
            if ReopenTimerManager.shared.fireDate(for: SessionSlotStore.activeIndex()) != nil {
                showTimer()
                updateTimeLabelForActiveSlot()
            } else {
                hideTimer()
            }
            fixStyles()
            setScreenshot()
            currentView.needsLayout = true
            currentView.updateConstraints()
        } else {
            applyEmptySlotUIOnly()
        }
        updateSlotButtonHighlights()
        refreshSlotBadges()
        syncExcludeSetupPopUp()
        checkAnyWindows()
        updatePreferredContentSize()
    }

    private func applyEmptySlotUIOnly() {
        // Keep the preview box reserved at its normal height so the popover
        // geometry does not jump when a slot flips between empty and filled.
        // Instead we hide the session controls and show a placeholder label.
        setSessionBoxPlaceholderVisible(true)
        hideTimer()
        fixStyles()
        setScreenshot()
    }

    // MARK: - Empty-slot placeholder

    private func buildNoSessionPlaceholderIfNeeded() {
        guard noSessionLabel == nil, let content = box.contentView else { return }
        let lbl = NSTextField(labelWithString: "No session saved in this slot.")
        lbl.font = NSFont.systemFont(ofSize: 13)
        lbl.textColor = NSColor(white: 0.65, alpha: 1)
        lbl.alignment = .center
        lbl.isHidden = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            lbl.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
            lbl.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16)
        ])
        noSessionLabel = lbl
    }

    /// Shows the "no session" placeholder and hides every other subview of the
    /// session preview box (preview image, labels, buttons). Or the reverse
    /// when `showPlaceholder` is `false`.
    ///
    /// The timer row (`timeWrapper`) is intentionally left alone — its own
    /// `showTimer()` / `hideTimer()` pair owns visibility and constraint height.
    /// Otherwise toggling the placeholder would briefly reveal a zero-height
    /// timer or collapse an active timer row.
    private func setSessionBoxPlaceholderVisible(_ showPlaceholder: Bool) {
        guard let content = box.contentView else { return }
        for sub in content.subviews {
            if sub === noSessionLabel {
                sub.isHidden = !showPlaceholder
            } else if sub === timeWrapper {
                continue
            } else {
                sub.isHidden = showPlaceholder
            }
        }
    }

    /// Tell the enclosing NSPopover that our content size may have changed so it
    /// resizes to match `view.fittingSize` (no leftover empty space, no clipping).
    private func updatePreferredContentSize() {
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        if size.width > 0 && size.height > 0 {
            preferredContentSize = size
        }
    }

    // MARK: - Session slots (1–6)

    private func buildSessionSlotSectionIfNeeded() {
        guard sessionSlotsRoot == nil else { return }
        guard let boxContent = optionsBox.contentView else { return }

        // The storyboard's options-box content view uses autoresizing, so a
        // bottom constraint on our slot column would only stretch the *content
        // view* inside the fixed-height box — leaving a big empty area below
        // the slots. Pin the content view to the box via Auto Layout so the
        // slot grid drives the box's real height.
        boxContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            boxContent.leadingAnchor.constraint(equalTo: optionsBox.leadingAnchor),
            boxContent.trailingAnchor.constraint(equalTo: optionsBox.trailingAnchor),
            boxContent.topAnchor.constraint(equalTo: optionsBox.topAnchor),
            boxContent.bottomAnchor.constraint(equalTo: optionsBox.bottomAnchor)
        ])

        let title = NSTextField(labelWithString: "Session")
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.alignment = .left
        title.textColor = NSColor(white: 0.65, alpha: 1)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var buttons: [NSButton] = []
        for i in 0..<SessionSlotStore.slotCount {
            let b = SlotButton(slotIndex: i, target: self, action: #selector(sessionSlotClicked(_:)))
            buttons.append(b)
        }
        sessionSlotButtons = buttons

        let row1 = NSStackView(views: Array(buttons[0..<3]))
        row1.orientation = .horizontal
        row1.spacing = 8
        row1.distribution = .fillEqually
        row1.alignment = .centerY

        let row2 = NSStackView(views: Array(buttons[3..<6]))
        row2.orientation = .horizontal
        row2.spacing = 8
        row2.distribution = .fillEqually
        row2.alignment = .centerY

        let col = NSStackView(views: [title, row1, row2])
        col.orientation = .vertical
        col.spacing = 8
        col.alignment = .width
        col.translatesAutoresizingMaskIntoConstraints = false

        boxContent.addSubview(col)
        sessionSlotsRoot = col

        let inset: CGFloat = 16
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 14),
            col.leadingAnchor.constraint(equalTo: boxContent.leadingAnchor, constant: inset),
            col.trailingAnchor.constraint(equalTo: boxContent.trailingAnchor, constant: -inset),
            col.bottomAnchor.constraint(equalTo: boxContent.bottomAnchor, constant: -inset),
            row1.heightAnchor.constraint(equalToConstant: 30),
            row2.heightAnchor.constraint(equalToConstant: 30)
        ])

        updateSlotButtonHighlights()
    }

    @objc private func sessionSlotClicked(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < SessionSlotStore.slotCount else { return }
        // Per-slot timers run independently; switching slots must not kill
        // the previously active slot's countdown (v2.6.0).
        SessionSlotStore.setActiveIndex(idx)
        refreshUIForActiveSlot()
    }

    private func updateSlotButtonHighlights() {
        let active = SessionSlotStore.activeIndex()
        for b in sessionSlotButtons {
            (b as? SlotButton)?.setActive(b.tag == active)
        }
    }

    private func applySessionSlotSectionStyle() {
        // Custom `SlotButton` handles its own drawing; nothing to do here.
    }

    // MARK: - Exclude setups (session presets)

    private func buildExcludeSetupRowIfNeeded() {
        guard excludeSetupStack == nil else { return }

        let label = NSTextField(labelWithString: "Session setup:")
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .right

        excludeSetupPopUp.target = self
        excludeSetupPopUp.action = #selector(excludeSetupModeChanged(_:))

        let edit = NSButton(title: "Edit…", target: self, action: #selector(openExcludeSetupEditor))
        edit.bezelStyle = .rounded

        let row = NSStackView(views: [label, excludeSetupPopUp, edit])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.distribution = .fill
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        excludeSetupPopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)

        currentView.addSubview(row)
        excludeSetupStack = row

        // Detach the save button from the options-box bottom and let Auto Layout
        // drive the whole column: options box → exclude row → save button → view bottom.
        // The storyboard's `containerHeight` constraint is left active but lowered
        // to priority 250, so the content-driven chain wins and the popover sizes
        // to fit (no leftover empty gap, no hidden save button).
        saveBelowOptionsConstraint.isActive = false

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: optionsBox.bottomAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: currentView.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(lessThanOrEqualTo: currentView.trailingAnchor, constant: -20),
            button.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 12),
            currentView.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: 20)
        ])

        applyExcludeSetupRowStyle()
    }

    /// Popover background is dark but AppDelegate forces `.aqua`; without this, labels read as dark-on-dark.
    /// On macOS 26+ with Liquid Glass enabled, the popover uses an adaptive
    /// appearance, so we fall back to semantic colors. If the user disabled
    /// Liquid Glass from the gear menu, we restore the legacy dark palette
    /// so labels stay readable on the dark popover.
    private func applyExcludeSetupRowStyle() {
        guard let row = excludeSetupStack else { return }
        if isLiquidGlassEnabled {
            // Let the row adopt the popover's (adaptive) appearance and use
            // semantic label colors — works on both light and dark glass.
            row.appearance = nil
            for v in row.arrangedSubviews {
                if let tf = v as? NSTextField {
                    tf.textColor = .labelColor
                } else if let pop = v as? NSPopUpButton {
                    pop.appearance = nil
                    let display = pop.title
                    if !display.isEmpty {
                        pop.attributedTitle = NSAttributedString(
                            string: display,
                            attributes: [.foregroundColor: NSColor.labelColor]
                        )
                    }
                } else if let btn = v as? NSButton {
                    btn.contentTintColor = .labelColor
                }
            }
            return
        }
        row.appearance = NSAppearance(named: .darkAqua)
        for v in row.arrangedSubviews {
            if let tf = v as? NSTextField {
                tf.textColor = NSColor(white: 0.92, alpha: 1)
            } else if let pop = v as? NSPopUpButton {
                pop.appearance = NSAppearance(named: .darkAqua)
                let fg = NSColor(white: 0.92, alpha: 1)
                let display = pop.title
                if !display.isEmpty {
                    pop.attributedTitle = NSAttributedString(string: display, attributes: [.foregroundColor: fg])
                }
            } else if let btn = v as? NSButton {
                btn.contentTintColor = NSColor(white: 0.88, alpha: 1)
            }
        }
    }

    private func syncExcludeSetupPopUp() {
        excludeSetupPopUp.removeAllItems()
        excludeSetupPopUp.addItem(withTitle: "All")
        let names = ExcludeSetupStore.loadDisplayNames()
        for n in names {
            excludeSetupPopUp.addItem(withTitle: n)
        }
        let activeSlot = SessionSlotStore.activeIndex()
        switch ExcludeSetupStore.mode(forSessionSlot: activeSlot) {
        case .all:
            excludeSetupPopUp.selectItem(at: 0)
        case .slot(let i):
            let idx = i + 1
            if idx < excludeSetupPopUp.numberOfItems {
                excludeSetupPopUp.selectItem(at: idx)
            } else {
                excludeSetupPopUp.selectItem(at: 0)
            }
        }
        applyExcludeSetupRowStyle()
    }

    @objc private func excludeSetupModeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let activeSlot = SessionSlotStore.activeIndex()
        let newMode: ExcludeSetupMode
        if idx == 0 {
            newMode = .all
        } else if idx >= 1, idx <= ExcludeSetupStore.slotCount {
            newMode = .slot(idx - 1)
        } else {
            return
        }
        ExcludeSetupStore.setMode(newMode, forSessionSlot: activeSlot)
        // Keep the legacy global mode in sync with the active slot so any code
        // still reading `currentMode()` sees the same value.
        ExcludeSetupStore.setCurrentMode(newMode)
        applyExcludeSetupRowStyle()
        checkAnyWindows()
    }

    // MARK: - Time dropdown binding (v2.6.0)

    /// Rebuild the `timeDropdown` menu from the active slot's current
    /// `reopenMode`. While in clock-time mode we insert a dynamic header
    /// item showing "At 13:30" (or "Mon, Tue · 13:30" when recurring) so
    /// the user sees their schedule at a glance without opening the sheet.
    /// Called from `refreshUIForActiveSlot` and after every timer edit.
    private func rebuildTimeDropdownForActiveSlot() {
        let slot = SessionSlotStore.slot(at: SessionSlotStore.activeIndex())
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Dynamic clock-time header (only present while the slot is in
        // clock-time mode). Clicking it re-opens the editor.
        if slot.reopenMode == .clockTime {
            let header = NSMenuItem(title: clockHeaderTitle(for: slot),
                                    action: nil,
                                    keyEquivalent: "")
            header.tag = clockDropdownItemTag
            menu.addItem(header)
            menu.addItem(NSMenuItem.separator())
        }

        // Duration choices. Keep wording in sync with the localized
        // storyboard defaults so existing screenshots / docs stay valid.
        // Per-item actions must stay nil — only `timeDropdown.action` fires.
        for title in ["15 minutes", "30 minutes", "1 hour", "5 hours"] {
            let it = NSMenuItem(title: title,
                                action: nil,
                                keyEquivalent: "")
            if slot.reopenMode == .duration,
               durationMinutes(for: title) == slot.reopenDurationMinutes {
                it.state = .on
            }
            menu.addItem(it)
        }
        menu.addItem(NSMenuItem.separator())

        let plannerItem = NSMenuItem(title: timePlannerMenuTitle,
                                     action: nil,
                                     keyEquivalent: "")
        plannerItem.tag = timePlannerMenuTag
        menu.addItem(plannerItem)

        timeDropdown.menu = menu

        // Select the item that matches the current mode.
        switch slot.reopenMode {
        case .clockTime:
            timeDropdown.selectItem(withTag: clockDropdownItemTag)
        case .duration:
            let title = titleForDuration(slot.reopenDurationMinutes)
            timeDropdown.selectItem(withTitle: title)
        case .off:
            // Leave the default selection (first duration) so the dropdown
            // reads sensibly when the user later ticks the checkbox.
            timeDropdown.selectItem(at: 0)
        }
    }

    private func clockHeaderTitle(for slot: SessionSlotStore.Slot) -> String {
        let hh = String(format: "%02d", max(0, min(23, slot.reopenClockHour)))
        let mm = String(format: "%02d", max(0, min(59, slot.reopenClockMinute)))
        let wd = Set(slot.reopenWeekdays)
        if wd.isEmpty {
            return "At \(hh):\(mm)"
        }
        return "\(weekdayListString(wd)) · \(hh):\(mm)"
    }

    private func durationMinutes(for title: String) -> Int? {
        switch title {
        case "15 minutes": return 15
        case "30 minutes": return 30
        case "1 hour":     return 60
        case "5 hours":    return 300
        default: return nil
        }
    }

    private func titleForDuration(_ minutes: Int) -> String {
        switch minutes {
        case 15:  return "15 minutes"
        case 30:  return "30 minutes"
        case 60:  return "1 hour"
        case 300: return "5 hours"
        default:  return "15 minutes"
        }
    }

    // MARK: - Clock-time sheet (v2.6.0)

    /// Present a compact programmatic sheet for picking HH:MM plus an
    /// optional weekday recurrence pattern. Reuses the storyboard-less
    /// window style already used by `ShortcutSettingsController`.
    private func presentClockTimeSheet() {
        if let existing = clockTimeSheetWindow, existing.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let slot = SessionSlotStore.slot(at: SessionSlotStore.activeIndex())
        let sheet = ClockTimeSheetController(
            initialHour: slot.reopenClockHour,
            initialMinute: slot.reopenClockMinute,
            initialWeekdays: Set(slot.reopenWeekdays)
        )
        sheet.onConfirm = { [weak self] hour, minute, weekdays in
            self?.applyClockTimeChoice(
                slotIndex: SessionSlotStore.activeIndex(),
                hour: hour,
                minute: minute,
                weekdays: weekdays
            )
        }
        sheet.onCancel = { [weak self] in
            // The user already pre-selected "At specific time…" in the
            // dropdown; if they cancel we put the selection back to
            // whatever the slot actually holds.
            self?.rebuildTimeDropdownForActiveSlot()
        }
        sheet.onWindowClosed = { [weak self] in
            self?.clockTimeSheetWindow = nil
        }
        let win = NSWindow(contentViewController: sheet)
        win.title = "Reopen schedule"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 400, height: 300))
        win.center()
        clockTimeSheetWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func applyClockTimeChoice(slotIndex: Int, hour: Int, minute: Int, weekdays: Set<Int>) {
        SessionTimerEditing.applyClockTime(
            slotIndex: slotIndex,
            hour: hour,
            minute: minute,
            weekdays: weekdays
        )
        // `laterSessionTimersChanged` refreshes the popover; no extra work here.
    }

    @objc private func openExcludeSetupEditor() {
        if let existing = excludeSetupEditorWindow, existing.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let editor = ExcludeSetupEditorController()
        editor.onFinished = { [weak self] in
            self?.syncExcludeSetupPopUp()
        }
        let win = NSWindow(contentViewController: editor)
        win.title = "Session setups"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 460, height: 400))
        win.center()
        excludeSetupEditorWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
