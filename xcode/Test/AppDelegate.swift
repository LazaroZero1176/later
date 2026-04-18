//
//  AppDelegate.swift
//  Later
//
//  Created by Alyssa X on 1/22/22.
//

import Cocoa
import KeyboardShortcuts


@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // IMPORTANT: The status item MUST be created after NSApplicationDidFinishLaunching
    // fires. Creating it as a class-level `let` initializer runs before NSApp has
    // fully set up its menu bar; on macOS 13+ with multi-display / notch setups this
    // can lead to the item being attached to a phantom menu bar (AX reports it at
    // e.g. y=1434 instead of y=0), making it invisible.
    var statusItem: NSStatusItem!
    let popoverView = NSPopover()
    var eventMonitor: EventMonitor?
    let defaults = UserDefaults.standard

    /// When the menu bar item is hidden, we anchor the popover to this tiny
    /// window at the top-center of the main display.
    private var fallbackAnchorWindow: NSWindow?

    /// Lazy window that hosts the `ShortcutSettingsController`. Created once
    /// on first "Configure shortcuts…" invocation; `isReleasedWhenClosed =
    /// false` so we can reopen it without re-instantiating the view.
    private var shortcutWindow: NSWindow?

    /// v2.7.0 — all six session slots' reopen timers in one place.
    private var timePlannerWindow: NSWindow?

    func runApp() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        guard let button = statusItem.button else {
            NSLog("Later: statusItem.button is nil — cannot create menu bar item")
            return
        }

        // Bundled "icon" asset is 32×32 — resize to the menu bar budget.
        // Keep the template rendering so the icon adapts to light/dark menubar.
        let menuBarSize = NSSize(width: 18, height: 18)
        if let img = NSImage(named: NSImage.Name("icon")) {
            img.isTemplate = true
            img.size = menuBarSize
            button.image = img
            NSLog("Later: status item using bundled 'icon' asset")
        } else if let symbol = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Later") {
            symbol.isTemplate = true
            symbol.size = menuBarSize
            button.image = symbol
            NSLog("Later: status item using SF Symbol fallback")
        } else {
            button.title = "L"
            NSLog("Later: status item using text fallback")
        }

        button.imagePosition = .imageOnly
        button.toolTip = "Later"
        button.target = self
        button.action = #selector(AppDelegate.togglePopover(_:))
        // Route both click types through togglePopover(_:), which sniffs the
        // event and either shows the popover (left) or the session quickbar
        // menu (right / control-click) — see v2.4.2 / ISSUE-33.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let vc = storyboard.instantiateController(withIdentifier: "ViewController1") as? ViewController else {
            NSLog("Later: Unable to instantiate ViewController from storyboard")
            return
        }
        popoverView.contentViewController = vc
        popoverView.behavior = .transient
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            if self.popoverView.isShown {
                self.closePopover(event)
            }
        }
        eventMonitor?.start()
    }


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Register (not set!) sensible defaults so user toggles are preserved across launches.
        defaults.register(defaults: [
            "ignoreSystem": true,
            "closeApps": false,
            "keepWindowsOpen": false,
            // v2.6.0 moved the "Reopen this session" flag to per-slot storage
            // (SessionSlotStore.Slot.reopenMode); the old global
            // `waitCheckbox` UserDefaults key is no longer read by anyone.
            "switchKey": false,
            "showDockIcon": true,
            "showMenuBarIcon": true,
            // On macOS 26 (Tahoe) and later the popover adopts the system
            // Liquid Glass material by default. Users who prefer the legacy
            // dark-tinted popover can disable this from the gear menu
            // (ViewController owns the toggle). Ignored on pre-Tahoe.
            "useLiquidGlass": true,
            // Keep these in sync with `ExcludeSetupStore.defaultDisplayNames` and
            // `ExcludeSetupMode.all.rawValue`. `ExcludeSetupStore.migrateIfNeeded()`
            // is the single source of truth for first-launch seeding and
            // German→English locale migration; this register call only ensures
            // safe values exist before that migration runs.
            "excludeSetup.displayNames": ["Work", "Presentation", "Coding", "Entertainment"],
            "excludeSetup.mode": "all"
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceSettingsChanged),
            name: .laterAppearanceChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverWillClose(_:)),
            name: NSPopover.willCloseNotification,
            object: popoverView
        )

        // IMPORTANT: Create status item while the app is .accessory. Menubar
        // extras created under .regular get placed into a phantom application
        // menubar on multi-display setups instead of the system extras bar.
        NSApp.setActivationPolicy(.accessory)
        runApp()

        // Wire global shortcuts (v2.5.0). Migration of the legacy `switchKey`
        // polarity lives in `ViewController.migrateShortcutsV2IfNeeded()` and
        // must run before we decide whether to enable or disable here, so we
        // force the view to load first. Touching `.view` is idempotent.
        if let vc = popoverView.contentViewController as? ViewController {
            _ = vc.view
        }
        installShortcutListeners()
        applyShortcutMasterToggle()

        // Per-slot reopen timers (v2.6.0). The manager owns the actual
        // Timer instances and persists each slot's absolute fire date, so
        // timers survive an app quit. When a timer fires, it routes through
        // `restoreSessionGlobal()` on the loaded ViewController.
        ReopenTimerManager.shared.onFire = { [weak self] slotIdx in
            guard let self else { return }
            SessionSlotStore.setActiveIndex(slotIdx)
            self.runOnVC { $0.restoreSessionGlobal() }
        }
        ReopenTimerManager.shared.restoreFromDisk()

        // v2.8.0 — clock-time **Save windows for later** per slot (e.g. start of workday).
        ScheduledSaveTimerManager.shared.onSaveFire = { [weak self] slotIdx in
            guard let self else { return }
            SessionSlotStore.setActiveIndex(slotIdx)
            self.runOnVC { $0.saveSessionGlobal() }
        }
        ScheduledSaveTimerManager.shared.restoreFromDisk()

        // Apply Dock + menu bar visibility (reads showDockIcon / showMenuBarIcon).
        DispatchQueue.main.async { [weak self] in
            self?.applyAppearanceSettings()
        }
    }

    @objc private func appearanceSettingsChanged() {
        applyAppearanceSettings()
    }

    @objc private func popoverWillClose(_ notification: Notification) {
        dismissFallbackAnchor()
    }

    /// Controls Dock visibility via activation policy and the status item via
    /// `isVisible`. Called at launch and when the user changes the toggles.
    func applyAppearanceSettings() {
        let showDock = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        let showMenu = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true

        if statusItem != nil {
            statusItem.isVisible = showMenu
        }

        // `.regular` → Dock tile; `.accessory` → menu-bar-only agent (no Dock).
        let policy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When the user clicks the Dock icon (no visible windows), toggle the popover.
        NSApp.activate(ignoringOtherApps: true)
        if !flag {
            togglePopover(nil)
        }
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        eventMonitor?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        // Sniff the current event so a right-click (or Ctrl-click) on the
        // status item opens the session quickbar instead of the popover.
        // Left-click falls through to the normal show/hide toggle.
        if let ev = NSApp.currentEvent,
           ev.type == .rightMouseUp
               || (ev.type == .leftMouseUp && ev.modifierFlags.contains(.control)) {
            showQuickMenu()
            return
        }
        togglePopoverInternal(sender)
    }

    /// Pure show/hide toggle for the popover, used by the left-click path
    /// above and by the "Open Later..." item inside the quickbar.
    private func togglePopoverInternal(_ sender: AnyObject?) {
        if popoverView.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    @objc private func togglePopoverFromMenu(_ sender: Any?) {
        togglePopoverInternal(sender as AnyObject?)
    }

    func showPopover(_ sender: AnyObject?) {
        popoverView.animates = true
        reapplyPopoverAppearance()

        if let button = statusItem.button,
           statusItem.isVisible,
           button.window != nil,
           isViewOnAnyScreen(button) {
            dismissFallbackAnchor()
            popoverView.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        } else {
            let anchor = presentFallbackAnchor()
            popoverView.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        eventMonitor?.start()
    }

    func closePopover(_ sender: AnyObject?) {
        popoverView.performClose(sender)
        dismissFallbackAnchor()
        eventMonitor?.stop()
    }

    // MARK: - Session quickbar (right-click on status item)

    /// Build and present a fresh `NSMenu` listing every session slot plus the
    /// regular entry points. Called on right-click / Ctrl-click of the status
    /// item (see `togglePopover`). The menu is rebuilt every time so slot
    /// names and the active-slot checkmark reflect the current state.
    private func showQuickMenu() {
        guard let button = statusItem?.button,
              statusItem.isVisible,
              button.window != nil,
              isViewOnAnyScreen(button) else {
            // Without a visible status-item button we cannot anchor an NSMenu.
            // Fall back to the popover (which has its own fallback anchor) so
            // a right-click still does something useful.
            togglePopoverInternal(nil)
            return
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Sessions", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let active = SessionSlotStore.activeIndex()
        for i in 0..<SessionSlotStore.slotCount {
            let slot = SessionSlotStore.slot(at: i)
            let title: String
            if slot.hasSession {
                title = "Slot \(i + 1) — \(slot.sessionName)"
            } else {
                title = "Slot \(i + 1) — empty"
            }
            let item = NSMenuItem(title: title,
                                  action: #selector(quickRestoreSlot(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = i
            item.isEnabled = slot.hasSession
            item.state = (i == active) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Save-to-slot submenu — the "boss is coming, make it clean" panic
        // button. Picking a slot sets it active and runs saveSessionGlobal(),
        // which screenshots, records the running apps, and then hides/closes
        // them per the popover's current exclude/close settings. Overwrites
        // the slot's previous contents without confirmation — mirrors the
        // regular Save button's behavior.
        let saveRoot = NSMenuItem(title: "Save current session to…",
                                  action: nil,
                                  keyEquivalent: "")
        let saveSub = NSMenu()
        saveSub.autoenablesItems = false
        for i in 0..<SessionSlotStore.slotCount {
            let slot = SessionSlotStore.slot(at: i)
            let suffix: String
            if slot.hasSession {
                suffix = "overwrite \(slot.sessionName)"
            } else {
                suffix = "empty"
            }
            let item = NSMenuItem(title: "Slot \(i + 1) — \(suffix)",
                                  action: #selector(quickSaveSlot(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (i == active) ? .on : .off
            saveSub.addItem(item)
        }
        saveRoot.submenu = saveSub
        menu.addItem(saveRoot)

        menu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "Open Later…",
                                  action: #selector(togglePopoverFromMenu(_:)),
                                  keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        // Drop just below the button so the menu feels attached to the icon.
        let origin = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    @objc private func quickRestoreSlot(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0 && idx < SessionSlotStore.slotCount else { return }
        SessionSlotStore.setActiveIndex(idx)
        // `restoreSessionGlobal()` lives on ViewController and depends on
        // IBOutlets (e.g. `closeApps`). Make sure the view has been loaded
        // at least once before calling it, otherwise a cold-launch right-click
        // (popover never opened yet) would crash on a nil outlet.
        if let vc = popoverView.contentViewController as? ViewController {
            // Force the view (and IBOutlets + viewDidLoad) to load if the
            // popover has never been shown. `loadViewIfNeeded()` would be
            // nicer but is macOS 14+; touching `.view` is the 13.0-compatible
            // equivalent and is idempotent.
            _ = vc.view
            vc.restoreSessionGlobal()
        }
    }

    @objc private func quickSaveSlot(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0 && idx < SessionSlotStore.slotCount else { return }
        SessionSlotStore.setActiveIndex(idx)
        if let vc = popoverView.contentViewController as? ViewController {
            // Same cold-launch guard as quickRestoreSlot: force the view to
            // load before saveSessionGlobal() runs, since it touches outlets
            // (`button`, `noSessionLabel`, ...) to reflect the saved state.
            _ = vc.view
            vc.saveSessionGlobal()
        }
    }

    // MARK: - Global shortcuts (v2.5.0)

    /// Run `body` on the popover's `ViewController`, loading its view first
    /// so IBOutlets are guaranteed to be wired. Safe to call from any
    /// menubar / shortcut entry point, including a cold launch where the
    /// popover has never been shown.
    private func runOnVC(_ body: (ViewController) -> Void) {
        guard let vc = popoverView.contentViewController as? ViewController else { return }
        _ = vc.view
        body(vc)
    }

    /// Wire the eight named shortcuts (`saveActiveSession`,
    /// `restoreActiveSession`, `restoreSlot1…6`) to their handlers. Called
    /// once, at startup. The handlers intentionally do not open the popover
    /// — same philosophy as the right-click quickbar: shortcuts are a
    /// zero-friction action, not a UI trigger.
    func installShortcutListeners() {
        KeyboardShortcuts.onKeyDown(for: .saveActiveSession) { [weak self] in
            self?.runOnVC { $0.saveSessionGlobal() }
        }
        KeyboardShortcuts.onKeyDown(for: .restoreActiveSession) { [weak self] in
            self?.runOnVC { $0.restoreSessionGlobal() }
        }
        for (idx, name) in KeyboardShortcuts.Name.allSlotRestore.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                guard idx >= 0 && idx < SessionSlotStore.slotCount else { return }
                SessionSlotStore.setActiveIndex(idx)
                self?.runOnVC { $0.restoreSessionGlobal() }
            }
        }
    }

    /// Enable or disable every app shortcut at once, honoring the
    /// `switchKey` default. Called at startup (after
    /// `installShortcutListeners()`) and whenever the user flips the
    /// "Enable global shortcuts" gear-menu entry. The recordings stay
    /// persisted either way — disabling only suppresses the handlers.
    ///
    /// Note: `switchKey` keeps its legacy polarity (`true` = disabled) to
    /// preserve the v2.4.x `UserDefaults` value during upgrades. The new
    /// gear-menu label ("Enable global shortcuts") flips the sign visually
    /// via a `.on` state when the default is `false`.
    func applyShortcutMasterToggle() {
        if defaults.bool(forKey: "switchKey") {
            KeyboardShortcuts.disable(KeyboardShortcuts.Name.allAppShortcuts)
        } else {
            KeyboardShortcuts.enable(KeyboardShortcuts.Name.allAppShortcuts)
        }
    }

    /// Present the modeless "Shortcuts" settings window. Invoked from the
    /// gear menu entry that replaces the legacy "Disable all shortcuts"
    /// toggle. The window is lazy-created on first call and reused after.
    @objc func openShortcutSettings(_ sender: Any?) {
        if shortcutWindow == nil {
            let vc = ShortcutSettingsController()
            let window = NSWindow(contentViewController: vc)
            window.styleMask = [.titled, .closable]
            window.title = "Shortcuts"
            window.isReleasedWhenClosed = false
            window.center()
            shortcutWindow = window
        }
        // Bring the app to the foreground so the window actually focuses —
        // by default we run as .accessory when the Dock icon is hidden.
        NSApp.activate(ignoringOtherApps: true)
        shortcutWindow?.makeKeyAndOrderFront(sender)
    }

    /// Central UI for planning per-slot reopen timers (v2.7.0). Invoked from
    /// the gear menu and from the popover's "Time planner…" dropdown entry.
    @objc func openTimePlanner(_ sender: Any?) {
        if let w = timePlannerWindow, w.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(sender)
            return
        }
        let vc = SessionTimePlannerController()
        let win = NSWindow(contentViewController: vc)
        win.title = "Time planner"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.contentMinSize = NSSize(width: 500, height: 600)
        win.setContentSize(NSSize(width: 520, height: 620))
        win.center()
        timePlannerWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(sender)
    }

    /// Apply or clear the legacy dark popover overrides based on the user's
    /// Liquid Glass preference. Called both before first-show and whenever
    /// the user toggles the gear-menu item while the popover is already open.
    ///
    /// On macOS 26+ with Liquid Glass enabled we leave the popover alone so
    /// the system material can render. In every other case — pre-Tahoe, or
    /// Tahoe with the opt-out toggled off — we reinstate the dark panel look
    /// that shipped through v2.3.x.
    func reapplyPopoverAppearance() {
        let useGlass: Bool
        if #available(macOS 26.0, *) {
            useGlass = defaults.object(forKey: "useLiquidGlass") as? Bool ?? true
        } else {
            useGlass = false
        }
        if useGlass {
            // Let the system render Liquid Glass. Clear any previous override.
            popoverView.backgroundColor = nil
            popoverView.appearance = nil
        } else {
            popoverView.backgroundColor = #colorLiteral(red: 0.1490048468, green: 0.1490279436, blue: 0.1489969194, alpha: 1)
            popoverView.appearance = NSAppearance(named: .aqua)
        }
    }

    private func isViewOnAnyScreen(_ view: NSView) -> Bool {
        guard let window = view.window else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    @discardableResult
    private func presentFallbackAnchor() -> NSView {
        if let existing = fallbackAnchorWindow, let v = existing.contentView {
            return v
        }
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let f = NSRect(x: screen.frame.midX - 1,
                       y: screen.frame.maxY - 2,
                       width: 2,
                       height: 2)
        let win = NSWindow(contentRect: f,
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        win.level = .statusBar
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: f.size))
        win.contentView = view
        win.orderFrontRegardless()
        fallbackAnchorWindow = win
        return view
    }

    private func dismissFallbackAnchor() {
        fallbackAnchorWindow?.orderOut(nil)
        fallbackAnchorWindow = nil
    }

}

extension Notification.Name {
    static let laterAppearanceChanged = Notification.Name("com.alyssaxuu.Later.appearanceChanged")
}

extension NSPopover {

    private struct Keys {
        static var backgroundViewKey: UInt8 = 0
    }

    private var backgroundView: NSView {
        let bgView = objc_getAssociatedObject(self, &Keys.backgroundViewKey) as? NSView
        if let view = bgView {
            return view
        }

        let view = NSView()
        objc_setAssociatedObject(self, &Keys.backgroundViewKey, view, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        NotificationCenter.default.addObserver(self, selector: #selector(popoverWillOpen(_:)), name: NSPopover.willShowNotification, object: nil)
        return view
    }

    @objc private func popoverWillOpen(_ notification: Notification) {
        if backgroundView.superview == nil {
            if let contentView = contentViewController?.view, let frameView = contentView.superview {
                frameView.wantsLayer = true
                backgroundView.frame = NSInsetRect(frameView.frame, 1, 1)
                backgroundView.autoresizingMask = [.width, .height]
                frameView.addSubview(backgroundView, positioned: .below, relativeTo: contentView)
            }
        }
    }

    var backgroundColor: NSColor? {
        get {
            if let bgColor = backgroundView.layer?.backgroundColor {
                return NSColor(cgColor: bgColor)
            }
            return nil
        }
        set {
            backgroundView.wantsLayer = true
            backgroundView.layer?.backgroundColor = newValue?.cgColor
            backgroundView.layer?.borderColor = newValue?.cgColor
        }
    }
}
