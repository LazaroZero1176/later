//
//  ViewController.swift
//  Test
//
//  Created by Alyssa X on 1/22/22.
//

import Cocoa
import CoreGraphics
import LaunchAtLogin
import HotKey
@preconcurrency import ScreenCaptureKit

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

    var checkKey = NSMenuItem(title: "Disable all shortcuts", action: #selector(switchKey), keyEquivalent: "")

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


    var timer = Timer()
    var timerCount = Timer()
    let settingsMenu = NSMenu()
    var count: Double = 0.0


    @IBOutlet weak var boxHeight: NSLayoutConstraint!
    @IBOutlet weak var topBoxSpacing: NSLayoutConstraint!
    @IBOutlet weak var containerHeight: NSLayoutConstraint!
    @IBOutlet weak var optionsBox: NSBox!
    @IBOutlet weak var saveBelowOptionsConstraint: NSLayoutConstraint!

    private var excludeSetupStack: NSStackView?
    private let excludeSetupPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private weak var excludeSetupEditorWindow: NSWindow?

    let defaults = UserDefaults.standard

    // UserDefaults keys for persisted session data.
    private enum Keys {
        static let session = "session"
        static let lastState = "lastState"
        static let date = "date"
        static let sessionName = "sessionName"
        static let sessionFullName = "sessionFullName"
        static let totalSessions = "totalSessions"
        /// Legacy: flat array of executable URLs (v1.x).
        static let appsLegacy = "apps"
        static let appNames = "appNames"
        /// New: array of bundle identifiers. Preferred for restore.
        static let appBundleIDs = "appBundleIDs"
    }

    // MARK: - Hotkeys

    private var closeKey: HotKey? {
        didSet {
            closeKey?.keyDownHandler = { [weak self] in
                guard let self else { return }
                Task { @MainActor in self.saveSessionGlobal() }
            }
        }
    }

    private var restoreKey: HotKey? {
        didSet {
            restoreKey?.keyDownHandler = { [weak self] in
                guard let self else { return }
                Task { @MainActor in self.restoreSessionGlobal() }
            }
        }
    }

    var observers = [NSKeyValueObservation]()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        checkbox.state = LaunchAtLogin.isEnabled ? .on : .off
        closeApps.state = defaults.bool(forKey: "closeApps") ? .on : .off
        ignoreFinder.state = defaults.bool(forKey: "ignoreSystem") ? .on : .off
        keepWindowsOpen.state = defaults.bool(forKey: "keepWindowsOpen") ? .on : .off
        waitCheckbox.state = defaults.bool(forKey: "waitCheckbox") ? .on : .off

        if defaults.bool(forKey: "switchKey") {
            checkKey.state = .on
            closeKey = nil
            restoreKey = nil
        } else {
            checkKey.state = .off
            closeKey = HotKey(key: .l, modifiers: [.command, .shift])
            restoreKey = HotKey(key: .r, modifiers: [.command, .shift])
        }

        if defaults.bool(forKey: Keys.session) {
            updateSession()
        } else {
            noSessions()
        }

        setScreenshot()
        fixStyles()
        setUpMenu()
        observeModel()

        ExcludeSetupStore.migrateIfNeeded()
        buildExcludeSetupRowIfNeeded()
        syncExcludeSetupPopUp()
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

    // MARK: - Timer

    @objc func counter() {
        if count >= 0 {
            count -= 1.0
            hmsFrom(seconds: Int(count)) { hours, minutes, seconds in
                let h = self.getStringFrom(seconds: hours)
                let m = self.getStringFrom(seconds: minutes)
                let s = self.getStringFrom(seconds: seconds)
                self.timeLabel.stringValue = "Reopening in \(h):\(m):\(s)"
            }
        } else {
            timerCount.invalidate()
        }
    }

    func waitForSession() {
        // Default to 15 min instead of dev-leftover 10 s (ISSUE-20).
        var time: Double = 60 * 15
        switch timeDropdown.titleOfSelectedItem {
        case "15 minutes": time = 60 * 15
        case "30 minutes": time = 60 * 30
        case "1 hour":     time = 60 * 60
        case "5 hours":    time = 60 * 60 * 5
        default: break
        }
        count = time
        hmsFrom(seconds: Int(count)) { hours, minutes, seconds in
            let h = self.getStringFrom(seconds: hours)
            let m = self.getStringFrom(seconds: minutes)
            let s = self.getStringFrom(seconds: seconds)
            self.timeLabel.stringValue = "Reopening in \(h):\(m):\(s)"
        }
        timer = Timer.scheduledTimer(timeInterval: time, target: self, selector: #selector(restoreSessionGlobal), userInfo: nil, repeats: false)
        timerCount = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(counter), userInfo: nil, repeats: true)
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
        let mode = ExcludeSetupStore.currentMode()
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
        guard let url = URL(string: "https://github.com/alyssaxuu/later") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func checkForUpdates() {
        // Use Sparkle to check for updates, not relevant in this version.
    }

    @objc func switchKey() {
        if checkKey.state == .on {
            checkKey.state = .off
            defaults.set(false, forKey: "switchKey")
            closeKey = HotKey(key: .l, modifiers: [.command, .shift])
            restoreKey = HotKey(key: .r, modifiers: [.command, .shift])
        } else {
            checkKey.state = .on
            defaults.set(true, forKey: "switchKey")
            restoreKey = nil
            closeKey = nil
        }
    }

    func setUpMenu() {
        menuItemShowDock.target = self
        menuItemShowMenuBar.target = self

        self.settingsMenu.addItem(NSMenuItem(title: "Visit website", action: #selector(openURL), keyEquivalent: ""))
        self.settingsMenu.addItem(checkKey)
        self.settingsMenu.addItem(NSMenuItem.separator())
        self.settingsMenu.addItem(menuItemShowDock)
        self.settingsMenu.addItem(menuItemShowMenuBar)
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

    private static func screenshotURL() -> URL? {
        return appSupportDirectory()?.appendingPathComponent("screenshot.jpg", isDirectory: false)
    }

    func setScreenshot() {
        guard let fileUrl = Self.screenshotURL() else { return }
        preview.image = NSImage(byReferencing: fileUrl)
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
        if #available(macOS 14.0, *) {
            Task.detached(priority: .userInitiated) {
                await Self.captureViaScreenCaptureKit()
            }
        } else {
            captureLegacy()
        }
    }

    @available(macOS 14.0, *)
    private static func captureViaScreenCaptureKit() async {
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
            guard let url = screenshotURL() else { return }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }
            try data.write(to: url, options: .atomic)
        } catch {
            // Likely the user has not granted Screen Recording permission yet.
            NSLog("Later: screenshot failed: \(error.localizedDescription)")
        }
    }

    private func captureLegacy() {
        guard let url = Self.screenshotURL() else { return }
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

    func getCurrentDate() {
        let currentDateTime = Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .medium
        defaults.set(formatter.string(from: currentDateTime), forKey: Keys.date)
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
        defaults.set(waitCheckbox.state == .on, forKey: "waitCheckbox")
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
        timer.invalidate()
        timerCount.invalidate()
        hideTimer()
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

        defaults.set(lastState, forKey: Keys.lastState)
        defaults.set(legacyURLs, forKey: Keys.appsLegacy)
        defaults.set(bundleIDs, forKey: Keys.appBundleIDs)
        defaults.set(arrayNames, forKey: Keys.appNames)
        defaults.set(sessionName, forKey: Keys.sessionName)
        defaults.set(sessionFull, forKey: Keys.sessionFullName)
        defaults.set(String(totalSessions), forKey: Keys.totalSessions)
        getCurrentDate()
        updateSession()
        if waitCheckbox.state == .on {
            waitForSession()
        }

        (NSApp.delegate as? AppDelegate)?.closePopover(self)
    }

    // MARK: - Restore session

    /// Reopen an app, preferring a bundle identifier lookup via LaunchServices (ISSUE-11, SEC-05).
    /// Falls back to legacy executable URL only if that fails.
    private func activate(name: String, bundleID: String?, legacyURL: String?) {
        // Already running → just unhide.
        if let bid = bundleID, !bid.isEmpty,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
            running.unhide()
            return
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
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
        if closeApps.state == .on {
            for app in NSWorkspace.shared.runningApplications where shouldInclude(app) {
                if app.bundleIdentifier == "com.apple.Terminal" { continue }
                app.terminate()
            }
        }

        let names = defaults.array(forKey: Keys.appNames) as? [String] ?? []
        let bundleIDs = defaults.array(forKey: Keys.appBundleIDs) as? [String] ?? []
        let legacyURLs = defaults.array(forKey: Keys.appsLegacy) as? [String] ?? []

        let count = names.count
        for i in 0..<count {
            let name = names[i]
            let bid = i < bundleIDs.count ? bundleIDs[i] : nil
            let url = i < legacyURLs.count ? legacyURLs[i] : nil
            activate(name: name, bundleID: bid, legacyURL: url)
        }
        noSessions()

        (NSApp.delegate as? AppDelegate)?.closePopover(self)
    }

    // MARK: - Popover states

    func noSessions() {
        defaults.set(false, forKey: Keys.session)
        boxHeight.constant = 0
        topBoxSpacing.constant = 0
        containerHeight.constant = 466
        currentView.needsLayout = true
        currentView.updateConstraints()
        fixStyles()
        checkAnyWindows()
    }

    func hmsFrom(seconds: Int, completion: @escaping (_ hours: Int, _ minutes: Int, _ seconds: Int) -> Void) {
        completion(seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
    }

    func getStringFrom(seconds: Int) -> String {
        return seconds < 10 ? "0\(seconds)" : "\(seconds)"
    }

    func updateSession() {
        defaults.set(true, forKey: Keys.session)
        if let dateString = defaults.string(forKey: Keys.date) {
            dateLabel.stringValue = dateString
            dateLabel.lineBreakMode = .byTruncatingTail
        }
        if let sessionName = defaults.string(forKey: Keys.sessionName) {
            sessionLabel.stringValue = sessionName
            sessionLabel.lineBreakMode = .byTruncatingTail
            if let sessionFullName = defaults.string(forKey: Keys.sessionFullName) {
                sessionLabel.toolTip = sessionFullName
            }
        }
        if let totalSessions = defaults.string(forKey: Keys.totalSessions) {
            numberOfSessions.title = totalSessions
        }
        if waitCheckbox.state == .on {
            showTimer()
        } else {
            hideTimer()
        }
        fixStyles()
        setScreenshot()
        topBoxSpacing.constant = 16
        containerHeight.constant = 686
        currentView.needsLayout = true
        currentView.updateConstraints()
        checkAnyWindows()
    }

    // MARK: - Exclude setups (session presets)

    private func buildExcludeSetupRowIfNeeded() {
        guard excludeSetupStack == nil else { return }

        let label = NSTextField(labelWithString: "Session-Setup:")
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .right

        excludeSetupPopUp.target = self
        excludeSetupPopUp.action = #selector(excludeSetupModeChanged(_:))

        let edit = NSButton(title: "Bearbeiten…", target: self, action: #selector(openExcludeSetupEditor))
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

        saveBelowOptionsConstraint.isActive = false

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: optionsBox.bottomAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: currentView.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(lessThanOrEqualTo: currentView.trailingAnchor, constant: -20),
            button.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 8)
        ])

        applyExcludeSetupRowStyle()
    }

    /// Popover background is dark but AppDelegate forces `.aqua`; without this, labels read as dark-on-dark.
    private func applyExcludeSetupRowStyle() {
        guard let row = excludeSetupStack else { return }
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
        excludeSetupPopUp.addItem(withTitle: "Alles")
        let names = ExcludeSetupStore.loadDisplayNames()
        for n in names {
            excludeSetupPopUp.addItem(withTitle: n)
        }
        switch ExcludeSetupStore.currentMode() {
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
        if idx == 0 {
            ExcludeSetupStore.setCurrentMode(.all)
        } else if idx >= 1, idx <= ExcludeSetupStore.slotCount {
            ExcludeSetupStore.setCurrentMode(.slot(idx - 1))
        }
        checkAnyWindows()
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
        win.title = "Session-Setups"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 460, height: 400))
        win.center()
        excludeSetupEditorWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
