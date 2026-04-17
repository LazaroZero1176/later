//
//  AppDelegate.swift
//  Later
//
//  Created by Alyssa X on 1/22/22.
//

import Cocoa
import SwiftUI


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
            "switchKey": false
        ])

        // IMPORTANT: Create status item while the app is .accessory. Menubar
        // extras created under .regular get placed into a phantom application
        // menubar on multi-display setups instead of the system extras bar.
        NSApp.setActivationPolicy(.accessory)
        runApp()

        // Then flip to .regular so the Dock icon stays visible as a fallback
        // entry point. The status item is already attached to the system
        // extras menubar at this point.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When the user clicks the Dock icon (no visible windows), toggle the popover.
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
        if let button = statusItem.button {
            popoverView.backgroundColor = #colorLiteral(red: 0.1490048468, green: 0.1490279436, blue: 0.1489969194, alpha: 1)
            popoverView.appearance = NSAppearance(named: .aqua)
            popoverView.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
        eventMonitor?.start()
    }

    func closePopover(_ sender: AnyObject?) {
        popoverView.performClose(sender)
        eventMonitor?.stop()
    }


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
