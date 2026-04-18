//
//  AppDelegate.swift
//  Later
//
//  Created by Alyssa X on 1/22/22.
//

import Cocoa


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
            "waitCheckbox": false,
            "switchKey": false,
            "showDockIcon": true,
            "showMenuBarIcon": true,
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
        if popoverView.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    func showPopover(_ sender: AnyObject?) {
        popoverView.animates = true
        // On macOS 26 (Tahoe) and later the popover automatically adopts the
        // new Liquid Glass material. Overriding `backgroundColor` and forcing
        // `.aqua` would flatten it back to an opaque light panel, so we only
        // apply the legacy dark-tinted look on pre-Tahoe systems.
        if #available(macOS 26.0, *) {
            // Let Liquid Glass handle the backdrop. No overrides.
        } else {
            popoverView.backgroundColor = #colorLiteral(red: 0.1490048468, green: 0.1490279436, blue: 0.1489969194, alpha: 1)
            popoverView.appearance = NSAppearance(named: .aqua)
        }

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
