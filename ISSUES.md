# Later — Issue Tracker

> Audit ausgeführt am 2026-04-17 auf macOS 26.5 (Tahoe, Build 25F5053d).
> v2.2-Audit ausgeführt am 2026-04-18 auf demselben System, Fokus: neue Slot- und Setup-Stores.
> Basisversion: `alyssaxuu/later` @ `master` — Original-Binary: `Later.dmg` v1.91 (BuildMachineOSBuild 21F79, SDK macosx12.3).
> Aktueller Build (dieses Repo): **v2.7.5 (Build 22)**, ad-hoc signiert, macOS 13.0+ deployment target, Xcode 26.4.1 / macOS 26.4 SDK.
>
> Versionierungs-Konvention: ab v2.2 werden Minor-Bumps (2.2 → 2.3, 2.3 → 2.4) für Feature-/Fix-Releases verwendet. Ein Major-Bump (2.x → 3.0) bleibt Breaking-Changes oder größeren Umbauten vorbehalten. Reine Folge-Fixes zu einem gerade veröffentlichten Minor werden als Patch-Bump (z. B. 2.3 → 2.3.1) ausgeliefert, damit das letzte gute Minor klar erkennbar bleibt. `MARKETING_VERSION` in `project.pbxproj`, `CFBundleShortVersionString` in `Info.plist` und `LATER_VERSION` in `build-dmg.sh` müssen pro Release synchron erhöht werden.
> Test-Binary ist ad-hoc signiert (kein Developer-Team), `spctl -a -vv` meldet `rejected` → Nutzer muss Quarantäne-Attribut entfernen (siehe ISSUE-01).

---

## Zusammenfassung (warum das Build auf aktuellem macOS nicht startet)

Die mitgelieferte `Later.dmg` **kann auf macOS 15 (Sequoia) und macOS 26 (Tahoe) nicht mehr einfach per „Rechtsklick → Öffnen" gestartet werden** (Apple hat diesen Bypass entfernt). Selbst nach manueller Gatekeeper-Freigabe würde der Hauptablauf sofort crashen, weil:

1. `CGDisplayCreateImage` in macOS 14 deprecated wurde und ab macOS 15 ohne Screen-Recording-Permission bzw. gänzlich `nil` zurückgibt. Die App unwrappt das Ergebnis force (`!`), ergo Crash beim ersten „Save".
2. `SMLoginItemSetEnabled` (hinter `LaunchAtLogin.isEnabled`) wurde in macOS 13 durch `SMAppService` ersetzt. Die mitgelieferte Binary linkt noch gegen die Legacy-Symbole → stummer Fehler, Autostart wirkungslos.
3. `Info.plist` enthält `UIAppFonts` (iOS-Schlüssel). Unter macOS heißt der Key `ATSApplicationFontsPath` — die gebündelten Inter-Fonts werden daher **nie geladen**, weshalb das UI mit System-Fallbacks rendert.
4. `LSUIElement = false` + Laufzeit-Umschaltung auf `.accessory` erzeugt beim Start kurz einen Dock-Icon-Flash.
5. Die SwiftPM-Dependencies (`LaunchAtLogin`, `HotKey`) sind **auf Branches** (nicht Tags) gepinnt → Supply-Chain-Risiko + API-Drift.

---

## Legende

| Status | Bedeutung |
|---|---|
| OPEN | noch offen |
| FIX | in diesem Repo gefixt |
| DOC | in diesem Repo dokumentiert (kein Code-Fix möglich ohne Xcode/Signatur) |

| Severity | Bedeutung |
|---|---|
| CRIT | App startet/crasht auf aktuellem macOS |
| HIGH | Kernfunktion kaputt oder Sicherheitsrisiko |
| MED  | Stabilität/UX-Bug |
| LOW  | Aufräumen, keine Funktions­änderung |

---

## Issues

### ISSUE-01 · CRIT · DOC — Gatekeeper blockiert ad-hoc signiertes Build
- Beweis: `codesign -dv` → `Signature=adhoc`, `TeamIdentifier=not set`; `spctl -a -vv /Volumes/Later/Later.app` → `rejected`.
- Ursache: Die mitgelieferte `Later.dmg` wurde nur ad-hoc signiert und nie notarisiert. macOS 15+ hat den „Rechtsklick → Öffnen"-Bypass entfernt.
- Workaround für Endnutzer:
  1. `Later.app` nach `/Applications` kopieren
  2. Terminal: `xattr -dr com.apple.quarantine /Applications/Later.app`
  3. Alternativ: System Settings → Privacy & Security → „Open Anyway" neben dem blockierten Eintrag.
- Saubere Lösung: Build mit Apple Developer-ID neu signieren + notarisieren (`codesign`/`notarytool`). Siehe Abschnitt „Build-Anleitung" in `ISSUES.md`.

### ISSUE-02 · CRIT · FIX — `CGDisplayCreateImage` deprecated, nil auf macOS 15+
- Beweis: `nm Later.app/Contents/MacOS/Later | grep CGDisplayCreateImage` matcht; `ViewController.swift` Zeile 380 verwendet `CGDisplayCreateImage(activeDisplays[Int(i-1)])!`.
- Impact: Beim ersten „Save"-Klick Crash (Force-Unwrap eines `nil`). Screen-Recording-Permission wird nie angefragt.
- Fix:
  - Screenshot-Pfad: auf macOS 14+ via `ScreenCaptureKit` (async) bzw. Fallback per `CGWindowListCreateImage(.zero, .optionOnScreenOnly, kCGNullWindowID, .nominalResolution)` — beide brauchen Screen-Recording-Permission.
  - Force-Unwraps entfernen, Fehler swallow-safe; Screenshot ist rein visuelle Vorschau.
  - `NSScreenCaptureUsageDescription` in `Info.plist` ergänzen (siehe ISSUE-16).

### ISSUE-03 · CRIT · FIX — `LaunchAtLogin` via Legacy-SMLoginItem, Branch-Pin
- Beweis: `nm` matcht `_SMLoginItemSetEnabled`; `project.pbxproj` pinnt `LaunchAtLogin` auf `branch = main` (nicht Tag).
- Impact: Autostart funktioniert auf macOS 13+ nicht mehr wie im Build zu sehen. Branch-Pin zieht bei Neubau eine inkompatible API.
- Fix:
  - Branch-Pin → Versions-Pin (z. B. `5.0.0`) auf `project.pbxproj` umstellen.
  - `LaunchAtLogin.isEnabled = true` im `applicationDidFinishLaunching` entfernen — darf nicht bei jedem Start erzwungen werden, Nutzer muss das explizit aktivieren (Checkbox ist vorhanden).

### ISSUE-04 · HIGH · FIX — `HotKey` auf Branch gepinnt
- Beweis: `project.pbxproj` → `repositoryURL = https://github.com/soffes/HotKey` mit `branch = master`.
- Impact: Supply-Chain-Risiko (beliebige Commits); möglicher Build-Break.
- Fix: Auf aktuellen Tag (`0.2.0`) umstellen.

### ISSUE-05 · HIGH · FIX — `UIAppFonts` ist iOS-Key, Fonts laden auf macOS nicht
- Beweis: `Info.plist` enthält `UIAppFonts`. Korrekt wäre `ATSApplicationFontsPath` (relativer Pfad innerhalb `Resources/`).
- Impact: Inter-Fonts werden nie registriert → UI verwendet Systemfont; Storyboard-Texte mit „Inter-Regular" fallen zurück.
- Fix: `UIAppFonts` entfernen, `ATSApplicationFontsPath = "Fonts"` setzen und Fonts-Ordner korrekt als Resource bündeln. Als Übergangslösung die Fonts in `viewDidLoad` programmatisch via `CTFontManagerRegisterFontURLs` registrieren.

### ISSUE-06 · MED · FIX — `LSUIElement = false` + `.accessory` zur Laufzeit → Dock-Icon-Flash
- Beweis: `Info.plist: LSUIElement = false`; `AppDelegate.applicationDidFinishLaunching` ruft `NSApp.setActivationPolicy(.accessory)`.
- Impact: Dock-Icon blitzt 0.5–1 s auf, App erscheint kurz im Cmd-Tab.
- Fix-Historie: Erst `LSUIElement = true` gesetzt. **Wieder zurückgenommen** (siehe ISSUE-23), da Menubar-only-Modus in Kombination mit Menubar-Managern (Bartender/Barbee) und/oder ungewöhnlichen Multi-Display-Layouts das Status-Item unerreichbar macht. Finales Verhalten: `LSUIElement = false` + `.regular`-Activation-Policy → Dock-Icon bleibt sichtbar, dafür ist die App immer reachable. Klick auf den Dock-Icon öffnet das Popover (via `applicationShouldHandleReopen`).

### ISSUE-07 · HIGH · FIX — „System Preferences" als Ignore-Liste hardcoded
- Beweis: `ViewController.swift` Zeile 182, 462, 495, 569: String `"System Preferences"`.
- Impact: macOS 13 benannte die App in „System Settings" um. Aktuelle Settings-App wird als reguläre App behandelt — also versteckt/geschlossen, obwohl Nutzer „Ignore system apps" aktiviert hat.
- Fix: Helper `isSystemApp(_:)` einführen, prüfe Bundle-Identifier (`com.apple.systempreferences`, `com.apple.finder`, `com.apple.ActivityMonitor`, `com.apple.AppStore`) — robust gegen Locale & Umbenennungen.

### ISSUE-08 · HIGH · FIX — Force-Unwraps führen zu Crashes
- Beweis:
  - `runningApplication.executableURL!.absoluteString` (ViewController.swift:466, 497)
  - `runningApplication.localizedName!` (:467, 481, 498, 511, …)
  - `CGDisplayCreateImage(...)!` (:380)
  - `NSWorkspace.shared.frontmostApplication!` (:455)
  - `self!` in HotKey-Handlern (:58, 70)
  - `defaults.object(forKey: …)` Kette ohne Prüfung auf gleiche Länge
- Impact: Apps ohne `localizedName` (helper, Background-Services, XPC) lassen die App hart crashen.
- Fix: Alle `!` durch `guard let`/`if let`/`??` ersetzen, Length-Mismatch abfangen.

### ISSUE-09 · MED · FIX — Memory-Leak in `takeScreenshot`
- Beweis: `ViewController.swift:369` `UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: allocated)` ohne passendes `.deallocate()`.
- Fix: `defer { activeDisplays.deallocate() }` — oder direkt in ein `[CGDirectDisplayID](repeating: 0, count: allocated)`-Array mit `withUnsafeMutableBufferPointer`.

### ISSUE-10 · HIGH · FIX — Range-Crash bei 0 Displays
- Beweis: `ViewController.swift:377`: `for i in 1...displayCount` — crasht bei `displayCount == 0` (`1...0` ist illegal).
- Impact: Kopfloser Mac (Server / Screen Sharing) startet die App, erster „Save" crasht.
- Fix: `for i in 0..<Int(displayCount)` und `activeDisplays[i]` — oder ohnehin in ScreenCaptureKit-Pfad konsolidieren.

### ISSUE-11 · HIGH · FIX — Apps via `Process()` starten umgeht LaunchServices
- Beweis: `ViewController.swift:547-560` verwendet `Process()` mit der gespeicherten `executableURL`.
- Impact:
  - Funktioniert bei App-Bundles oft unvollständig (Framework-Helpers, XPC-Services werden nicht korrekt gestartet).
  - App wird unterhalb des LaunchServices-Tracking ausgeführt → Dock-Icon kann fehlen, Hintergrund-States inkonsistent.
  - Bei App-Updates ändert sich der Executable-Pfad → „Restore" schlägt stumm fehl.
- Fix: `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` mit dem **Bundle-URL** (nicht Executable-URL). Bundle-URL zusätzlich im UserDefaults speichern, mit Fallback über `NSWorkspace.urlForApplication(withBundleIdentifier:)`.

### ISSUE-12 · MED · FIX — `self!` in HotKey-Closures
- Beweis: ViewController.swift:58,70 `self!.saveSessionGlobal()` in `[weak self]` Closure.
- Fix: `guard let self else { return }`.

### ISSUE-13 · LOW · FIX — Quit-Shortcut erfordert Shift
- Beweis: `setUpMenu` setzt `keyEquivalent: "Q"` (Großbuchstabe). Korrekt: `"q"` (macOS schaltet Cmd+Q ohnehin dazu).
- Impact: Cmd+Q öffnet nicht, Cmd+Shift+Q schon.
- Fix: Kleinbuchstabe.

### ISSUE-14 · MED · FIX — `defaults.set(true, forKey: "ignoreSystem")` erzwingt Default bei jedem Start
- Beweis: `AppDelegate.swift:46` setzt den Wert unkonditional.
- Impact: Nutzer, der „Ignore system apps" deaktiviert, sieht es beim nächsten Start wieder auf „on".
- Fix: Stattdessen `UserDefaults.standard.register(defaults: ["ignoreSystem": true])` im `applicationDidFinishLaunching`.

### ISSUE-15 · LOW · FIX — Duplicate `NSStatusItem` in `ViewController`
- Beweis: ViewController.swift:46-47 legt erneut `NSStatusBar.system.statusItem(...)` + `NSPopover()` an — nie verwendet.
- Fix: Zeilen entfernen.

### ISSUE-16 · HIGH · FIX — Privacy-Strings & Entitlements
- Beweis: `Info.plist` hat weder `NSScreenCaptureUsageDescription` noch `CFBundleVersion`. `Test.entitlements` erlaubt `com.apple.security.cs.allow-jit` ohne Bedarf.
- Impact:
  - macOS 10.15+ zeigt Screen-Recording-Prompt nur mit Text — ohne String wird die App zwar weiter starten, aber der Prompt ist leer. Unter Hardened Runtime kann die Permission außerdem verweigert werden.
  - `allow-jit` öffnet unnötig Angriffsfläche (JIT-Speicher ist R+W+X).
  - Fehlender `CFBundleVersion` → Apple-Review/Sparkle-Updater brechen später.
- Fix:
  - `NSScreenCaptureUsageDescription` setzen.
  - `CFBundleVersion` = `CFBundleShortVersionString` spiegeln.
  - `allow-jit` aus Entitlements entfernen.

### ISSUE-17 · LOW · FIX — Twitter-URL (tot) im Menü
- Beweis: `ViewController.swift:197` → `https://twitter.com/alyssaxuu`.
- Fix: Auf Repo-URL umleiten: `https://github.com/alyssaxuu/later`.

### ISSUE-18 · MED · OPEN — Feste Storyboard-ID `ViewController1`
- Beweis: `AppDelegate.runApp()` `fatalError("Unable to find ViewController")` falls `instantiateController(withIdentifier: "ViewController1")` fehlschlägt. Storyboard hat ID `ViewController1` — okay, aber Fragil.
- Fix (optional): Graceful-Fallback statt `fatalError`.

### ISSUE-19 · MED · OPEN — Terminate-statt-Hide-Logik terminiert Finder nicht, aber andere System-Apps möglich
- Beweis: In `saveSessionGlobal` (keepWindowsOpen `.on`) wird `runningApplication.terminate()` aufgerufen — nur Finder ist ausgeschlossen; in `restoreSessionGlobal` (closeApps `.on`) werden alle non-Terminal non-Later terminiert.
- Impact: System-Daemons mit `activationPolicy == .regular` (selten, aber vorkommend) werden beendet.
- Fix: Gleicher `isSystemApp()`-Filter wie in ISSUE-07.

### ISSUE-20 · LOW · OPEN — Hardcodierte Fenstergrößen & Zeitdropdown
- Beweis: ViewController.swift:158 `var time: Double = 10` (10 Sekunden Default) ist ein Dev-Leftover; UI zeigt „15 minutes" etc., Default-Case ist 10 s.
- Fix: Default auf `60*15` setzen oder Dropdown-Default explizit synchron halten.

### ISSUE-21 · MED · FIX — Saved Sessions speichern plain String-Liste; keine Länge­n­prüfung
- Beweis: ViewController.swift:580 `for (index, app) in apps.enumerated() { activate(name:app, url:executables[index]) }` — Out-of-Bounds wenn `apps.count != executables.count`.
- Fix: `zip(apps, executables).forEach { … }`.

### ISSUE-22 · LOW · OPEN — `MACOSX_DEPLOYMENT_TARGET = 11.6` — künstlich niedrig
- Impact: Verhindert Nutzung moderner APIs (ScreenCaptureKit ab 12.3, SMAppService ab 13.0).
- Fix: Auf `13.0` anheben, Availability-Pfade in Swift sauber trennen.

### ISSUE-23 · HIGH · FIX — Menubar-Icon unsichtbar bei Multi-Display / Activation-Policy-Konflikt
- Beweis: Getestet auf Setup mit `Screen 0` (ASUS VA27A, Main, `0,0,2560,1440`) + `Screen 1` (MacBook Built-in, `2560,70,1512,982` — rechts daneben, 70 px tiefer). AX-Abfrage meldete das Status-Item auf `position=(-1, 1439)` `size=(26,24)` — also in einer Phantom-Menubar außerhalb jeder sichtbaren Region. Zusätzlich lief auf dem Testsystem der Menubar-Manager „Barbee" (Bartender-Fork) mit `newItemsAppearLocation = 0`, der neu angelegte Status-Items standardmäßig in den versteckten Bereich verschiebt.
- Ursache 1 (Code): Status-Item wurde als Klassen-Property-Initializer (`let statusItem = NSStatusBar.system.statusItem(withLength: 20)`) erzeugt, also **bevor** `NSApplicationDidFinishLaunching` feuert. Auf macOS 13+ kann so ein zu früh erzeugtes Item in eine „Phantom-Menubar" rutschen.
- Ursache 2 (Konfiguration): `NSApp.setActivationPolicy(.regular)` **vor** der Status-Item-Erstellung führt dazu, dass macOS das Item nicht korrekt in die System-Extras-Menubar einhängt, sondern in eine App-private Phantom-Bar (AX meldet `(-1, 1439)`).
- Ursache 3 (Asset): Das Bundle-Icon (`Assets.car → "icon"`) ist 32×32 px gerendert, die macOS-Menubar reserviert nur ~18 px Höhe. Ein überdimensioniertes Template-Icon kann zu einem unsichtbaren (Alpha=0) Button führen.
- Ursache 4 (System-Setting): macOS Sonoma+ erlaubt dem Nutzer pro App zu steuern, ob deren Menubar-Icon überhaupt angezeigt wird (System Settings → Control Center → „Menu Bar Only"). War im Test-Setup für „Later" auf „Nicht anzeigen" gesetzt.
- Impact: App läuft, ist aber „unsichtbar". Reproduktion im Test führte zu langem Debugging (kein Crash, nur phantom-positioniertes Item).
- Fix (mehrschichtig):
  1. Status-Item wird lazy **in** `applicationDidFinishLaunching` erzeugt (nicht mehr als Klassen-Property-Initializer).
  2. `NSApp.setActivationPolicy(.accessory)` **vor** Status-Item-Erstellung, anschließend via `DispatchQueue.main.async` Flip auf `.regular` → StatusItem landet korrekt in der System-Extras-Menubar **und** Dock-Icon bleibt sichtbar als Fallback.
  3. `applicationShouldHandleReopen(_:hasVisibleWindows:)` implementiert → Klick auf Dock-Icon öffnet Popover direkt.
  4. Bundle-Icon beim Setzen explizit auf `NSSize(width: 18, height: 18)` resized, `isTemplate = true`, `imagePosition = .imageOnly`. Fallback-Kette: bundled `icon` → SF Symbol `moon.zzz` → Text-Label „L".
  5. `statusItem.button?.toolTip = "Later"` gesetzt, damit Bartender/Alfred/etc. die App zuverlässig per Namen finden.
- Hinweis für Endnutzer:
  - Falls das Icon nach Installation nicht erscheint: **System Settings → Control Center → Menu Bar Only → „Later" auf „Don't Show"/„Show in Menu Bar" umstellen**.
  - Nutzer von Bartender/Barbee/Hidden Bar: „Later" dort einmalig auf „Show"/„Always Visible" setzen.
  - Unabhängig davon bleibt die App immer über den Dock-Icon erreichbar.

### ISSUE-24 · MED · FIX — v2.2: Deutsche Default-Namen in `AppDelegate.register(defaults:)`
- Beweis: `AppDelegate.applicationDidFinishLaunching` registrierte `"excludeSetup.displayNames": ["Arbeit", "Präsentation", "Coding", "Unterhaltung"]`.
- Impact: Inkonsistenz zur neuen Locale-Migration in `ExcludeSetupStore.migrateIfNeeded()` (englische Defaults). Wenn die Migrations-Flag `excludeSetup.localeMigratedToEnglish` je gelöscht / zurückgesetzt wird (z. B. Backup-Restore eines alten Profils), fallen Nutzer still auf deutsche Setup-Namen zurück, obwohl die restliche UI auf Englisch umgestellt ist.
- Fix: Register-Default auf `["Work", "Presentation", "Coding", "Entertainment"]` umgestellt; `ExcludeSetupStore.migrateIfNeeded()` bleibt Single-Source-of-Truth für die eigentliche Seeding- und Migrations-Logik.
- Datei: `xcode/Test/AppDelegate.swift`.

### ISSUE-25 · LOW · FIX — v2.2: `ExcludeSetupStore.migrateIfNeeded()` lief nach erstem UI-Refresh
- Beweis: `ViewController.viewDidLoad` rief `refreshUIForActiveSlot()` (und damit `syncExcludeSetupPopUp()`) vor `ExcludeSetupStore.migrateIfNeeded()` auf.
- Impact: Der erste Popover-Layout-Pass las die Setup-Daten, bevor die Store-Migration den Bundle-List-Blob / `keyMode` geseedet hatte. Funktional harmlos dank Fallbacks in `loadDisplayNames()`/`currentMode()`, aber die Aufrufreihenfolge widerspricht der Store-API und könnte beim Anbauen weiterer Migrationsschritte zu echten Bugs führen.
- Fix: Beide Migrationen (`SessionSlotStore.migrateIfNeeded()` + `ExcludeSetupStore.migrateIfNeeded()`) laufen jetzt ganz am Anfang von `viewDidLoad`; `syncExcludeSetupPopUp()` wird nur noch einmal aufgerufen (statt vorher implizit plus explizit).
- Datei: `xcode/Test/ViewController.swift`.

### ISSUE-26 · LOW · FIX — v2.2: Placeholder-Toggle machte `timeWrapper` zwangssichtbar
- Beweis: `setSessionBoxPlaceholderVisible(false)` iterierte über **alle** Subviews von `box.contentView` und setzte `isHidden = false`, auch für `timeWrapper`. Der Timer-Zustand wird aber durch `hideTimer()`/`showTimer()` verwaltet (Höhen-Constraint + `isHidden`).
- Impact: Beim Wechsel von einem leeren auf einen gefüllten Slot wurde `timeWrapper` kurz sichtbar, bevor der Timer-Branch ihn ggf. wieder versteckte — ein potentieller Layout-Flicker, und brittle gegenüber Reihenfolge-Änderungen.
- Fix: `timeWrapper` wird vom generischen Placeholder-Toggle ausgespart; Sichtbarkeit und Höhe bleiben allein bei `showTimer()`/`hideTimer()`.
- Datei: `xcode/Test/ViewController.swift`.

### ISSUE-27 · MED · FIX — v2.3: Restore löschte den aktiven Slot implizit
- Beweis: `ViewController.restoreSessionGlobal()` rief am Ende `noSessions()`, wodurch `SessionSlotStore.setSlot(.empty, at:)` den gerade restaurierten Slot (inkl. Screenshot-Datei) sofort wieder entfernte.
- Impact: Sessions konnten nicht als wiederverwendbare Presets dienen. Jeder Hotkey-/Timer-/Button-Restore zwang den Nutzer, danach manuell neu zu speichern. Besonders schmerzhaft in Kombination mit dem 15-Minuten-Auto-Restore des Timers — er hätte den Slot bei jedem Wake einmalig verbraucht.
- Fix: `restoreSessionGlobal()` ruft `noSessions()` nicht mehr auf, sondern `refreshUIForActiveSlot()`. Das Leeren eines Slots passiert ausschließlich noch über den X-Button (`hideBox:` → `noSessions()`). Zusätzlich verhindert ein `guard stored.hasSession else { NSSound.beep(); return }` am Anfang, dass ein Restore auf einem leeren Slot mit aktivierter „Close others"-Checkbox wahllos laufende Apps terminiert.
- Datei: `xcode/Test/ViewController.swift`.

### ISSUE-28 · LOW · FIX — v2.3: `closeApps` terminierte auch Session-eigene Apps
- Beweis: Die alte Close-Schleife in `restoreSessionGlobal()` beendete jede App, die `shouldInclude(_:)` passierte, und öffnete danach alle Slot-Apps über `activate(...)` neu. Apps, die bereits zur Ziel-Session gehörten, wurden also unnötig terminiert und sofort wieder gestartet.
- Impact: Sichtbares Flicker/Neuladen bei jedem Restore, unnötige Dokument-Reopen-Dialoge, und der Checkbox-Name „Close all apps when restoring" suggerierte einen destruktiveren Modus als gewünscht.
- Fix: Die Close-Schleife filtert jetzt gegen `targetBundleIDs`/`targetNames` (zusätzlich zu `com.apple.Terminal` und `isSystemApp`). Nur Apps, die **nicht** zur Ziel-Session gehören, werden beendet. `activate(...)` entdeckt laufende Session-Apps via Bundle-ID und macht lediglich `unhide()` — kein Neustart. Die Checkbox wurde entsprechend umbenannt in „Only apps from this session (close others)" (`Main.storyboard`, `US9-TX-iLZ`).
- Datei: `xcode/Test/ViewController.swift`, `xcode/Test/en.lproj/Main.storyboard`.

### ISSUE-29 · MED · FIX — v2.3.1: `activate()` übersah terminierende Apps beim Relaunch
- Beweis: `ViewController.activate(name:bundleID:legacyURL:)` (v2.3, Zeilen 685-695) nahm den ersten Treffer aus `NSRunningApplication.runningApplications(withBundleIdentifier:)` bzw. der Name-Fallback-Schleife und rief `unhide()` auf, ohne `isTerminated` zu prüfen. `app.terminate()` ist aber asynchron — gerade terminierte Apps bleiben für einen kurzen Moment mit `isTerminated == true` im `runningApplications`-Array.
- Impact: Klassisches v2.3-Preset-Szenario brach. Slot 1 ohne Claude wiederherstellen (Close-others an) → Claude bekommt `terminate()`. Sofort danach Slot 2 mit Claude wiederherstellen → `activate()` findet den noch nicht abgeschlossenen Claude-Prozess, `unhide()` ist no-op, Launch-Zweig wird übersprungen, Claude bleibt weg. Trat bei jedem Slot-Wechsel zwischen überlappenden Sessions auf.
- Fix: Beide Lookups filtern jetzt `!$0.isTerminated`, der Launch-Zweig greift in diesem Fall wieder und startet die App neu. Kein neuer Sleep/Retry nötig — `NSWorkspace.openApplication(at:)` ist gegenüber einer noch nicht ganz beendeten Instanz gutmütig.
- Datei: `xcode/Test/ViewController.swift`.

### ISSUE-36 · LOW · FEATURE — v2.6.0: Per-Slot-Reopen-Timer mit Duration/Clock-Time und Weekday-Recurrence
- Kontext: Bis v2.5.0 gab es genau einen globalen Reopen-Timer: die Checkbox „Reopen windows in" + das Dropdown mit 15 min / 30 min / 1 h / 5 h galten für *alle* Slots, und die Dropdown-Auswahl war überhaupt nicht persistiert (`timeDropdown.titleOfSelectedItem` wurde nur zur Laufzeit gelesen). Ein `Timer` auf dem `ViewController` feuerte `restoreSessionGlobal()` nach Ablauf — ein zweites Save auf einem anderen Slot killte den laufenden Countdown stumm. Es gab keinen Clock-Time-Modus („reopen um 09:00") und keine Wiederholung („täglich" oder „Mo/Di/Do"). Für echte Pausen- und Arbeitstag-Presets („Mittagspause um 13:30" / „jeden Werktag 09:00 Start") war das unbrauchbar.
- Scope v2.6.0: drei Ziele — (a) der Reopen-Timer wird pro Slot gespeichert und läuft unabhängig von anderen Slots, (b) zusätzlich zur Dauer gibt es einen Clock-Time-Modus, (c) Clock-Time bekommt optional ein Wiederholungs-Muster über Wochentage. Duration bleibt einmalig (einen wiederholenden „alle 15 min"-Reopen verhindert bewusst die UI).
- Umsetzung Datenmodell (`xcode/Test/SessionSlotStore.swift`):
  - `Slot` erweitert um fünf Felder: `reopenMode: ReopenMode` (`off`/`duration`/`clockTime`), `reopenDurationMinutes` (default `15`), `reopenClockHour` (`9`), `reopenClockMinute` (`0`), `reopenWeekdays: [Int]` (Calendar-Weekday-Werte 1=Sonntag…7=Samstag, leer = one-shot).
  - Custom `init(from: Decoder)` mit `decodeIfPresent(_:forKey:) ?? default` für die neuen Keys — pre-2.6.0-JSON-Blobs (das gesamte `UserDefaults[sessionSlots.payloadsJSON]`-Array) decodiert transparent auf `reopenMode = .off`, Default-Uhrzeit 09:00, keine Wiederholung. Kein expliziter Migration-Flag nötig, weil der erste `encode(to:)` das Slot dann im neuen Format zurückschreibt.
  - Neuer Computed-Helper `Slot.activeReopenPolicy` mappt Mode + Parameter auf `ReopenPolicy.off / .duration(minutes:) / .clockTime(hour:minute:weekdays:)`. Zentral, damit Manager + UI denselben Switch sehen.
- Umsetzung Manager (neu: `xcode/Test/ReopenTimerManager.swift`):
  - Singleton `ReopenTimerManager.shared`, hält `[Int: Timer]` (per Slot) plus `[Int: ReopenPolicy]` (damit der Feuer-Handler bei Recurrence rearmen kann, ohne das potenziell veränderte Slot-Model neu zu lesen).
  - Persistenz: absolute Fire-Date pro Slot als fixe 6-Element-Liste in `UserDefaults[reopen.fireDates]` (Einträge `Date` oder `NSNull`). Abwehr gegen falsche Array-Länge oder legacy TimeInterval-Werte im `loadFireDates()`. Keine relativen Dauern persistiert — wir rechnen zur Schedule-Zeit um.
  - `schedule(slotIndex:policy:)` cancelt zuerst, rechnet für `.duration` `now + minutes`, für `.clockTime` ohne Weekdays `Calendar.nextDate(...)`, mit Weekdays iteriert über alle selektierten `weekday` und nimmt das früheste Treffer-`Date`. `Timer.scheduledTimer` wird im `.common` RunLoop-Mode eingehängt, damit Sheets/Menüs den Callback nicht blockieren. `max(0.1, …)` schützt gegen Feuer-Daten, die beim Scheduling schon abgelaufen sind.
  - `fireSlot(_:policy:)` räumt Timer + Fire-Date auf, ruft `onFire(slotIndex)` auf dem Main-Thread, und rearmt *nur* bei `clockTime` mit nicht-leeren Weekdays: nächste Matching-`Date` berechnen, persistieren, neuen Timer setzen. One-shots (`duration` + `clockTime` ohne Weekdays) bleiben danach aus.
  - `restoreFromDisk()` läuft einmal aus `AppDelegate.applicationDidFinishLaunching`. Pro Slot die drei Fälle: (1) `.off` → vorhandene Fire-Date ist stale, löschen. (2) `.duration` → nur wenn Fire-Date gespeichert (ohne Save kein Timer möglich): vergangen → sofort feuern, zukünftig → reschedulen. (3) `.clockTime` → vergangen feuern + Recurrence-Rearm greift im `fireSlot`, zukünftig reschedulen, **und** der autonome Fallback: wenn die Fire-Date fehlt, aber Weekdays + `hasSession` gesetzt sind, die nächste Matching-`Date` neu berechnen und armen. Dadurch überlebt ein wochenlanger App-Quit einen „Mo–Fr 09:00"-Plan problemlos.
  - `isRecurring(slotIndex:)` + `remainingString(for:)` versorgen die UI mit dem Minimum, das sie für Badge + Tooltip + Countdown braucht — ohne den Manager-State öffentlich preiszugeben.
- Umsetzung UI (`xcode/Test/ViewController.swift`):
  - Globaler `timer`, `timerCount`, `waitForSession()`, `counter()`, `count`-Variable entfernt. Ersetzt durch einen einzigen UI-Ticker (`uiTicker: Timer?`), der 1× pro Sekunde die Slot-Buttons (`refreshSlotBadges`) plus das aktive `timeLabel` (`updateTimeLabelForActiveSlot`) aktualisiert und sich selbst deaktiviert, sobald kein Slot mehr armed ist. Der Ticker wird in `viewWillAppear` gestartet und in `viewDidDisappear` gestoppt, damit ein geschlossenes Popover keine Wakeups verursacht.
  - `waitCheckboxChange` schreibt jetzt in die aktive Slot-Instanz (`reopenMode = .off` bzw. `.duration`). Recurrierende Clock-Time-Schedules werden bei `waitCheckbox = on` sofort armiert (autonom), Duration bleibt save-getrieben.
  - Neuer `timeDropdownChanged(_:)`-Action: mappt „15 minutes" / „30 minutes" / „1 hour" / „5 hours" auf `duration`, der dynamische Header-Eintrag (Tag `clockDropdownItemTag`) und der „At specific time…"-Eintrag öffnen den neuen Clock-Time-Sheet. Die Menü-Items werden pro Slot-Wechsel via `rebuildTimeDropdownForActiveSlot()` komplett neu gebaut; der dynamische Header zeigt „At 13:30" (one-shot) oder „Mon, Tue, Thu · 13:30" (recurring).
  - `saveSessionGlobal()` merged die neuen Timer-Felder aus dem existierenden Slot beim Überschreiben (sonst würde ein Save die Reopen-Config zurücksetzen), delegiert dann `schedule(slotIndex:policy:)` an den Manager. `noSessions()` cancelt den Timer, behält aber Mode + Weekdays — damit läuft ein recurrentes Preset nach einem „Refill"-Save sofort wieder an (z. B. „chef kommt rein alles clean" → Slot leer → später Save → Schedule zieht wieder).
  - `sessionSlotClicked` ruft *nicht* mehr `timer.invalidate()` auf. Das war der klassische Bug „Slot 2 wählen killt den Timer von Slot 1"; per-Slot-Manager macht das obsolet.
  - `cancelTimeClick` wurde auf `ReopenTimerManager.shared.cancel(slotIndex:)` umgestellt, kein globales Timer-Leak mehr.
- Umsetzung SlotButton-Badge (`xcode/Test/ViewController.swift` `SlotButton`):
  - Neuer `CALayer`-Subchild (`badgeLayer`) oben rechts, 14×14, dunkles Halbtransparent-Circle-Background. Innerer `badgeImageLayer` zieht ein SF-Symbol (`clock` für one-shot, `arrow.clockwise` für recurring), per `tintedCGImage`-Helfer in Weiß getönt und als `CGImage` gesetzt, damit `CATransaction` die Updates ohne implizite Animation rausschreibt.
  - Neues Public-API `setTimerArmed(_ kind: ArmedKind, tooltip: String?)` mit `enum ArmedKind { none, oneShot, recurring }`. Der Ticker ruft das pro Slot einmal pro Sekunde auf; identische Werte skippen den Redraw.
- Umsetzung Clock-Time-Sheet (neu: `xcode/Test/ClockTimeSheetController.swift`):
  - Programmatischer `NSViewController` ohne Storyboard. Aufbau: Überschrift „Reopen this session", `NSDatePicker` auf `.hourMinute` für die Uhrzeit, sieben Checkboxen (Mon–Sun) in fester Reihenfolge (Calendar-Weekday-Werte werden über `tag` getragen, damit Sortierung unabhängig von Locale bleibt), Schnell-Buttons **Daily** (alle sieben anhaken) und **Clear** (alle abhaken), Hinweis-Label „Leave unchecked for a one-shot reopen at the chosen time.", Cancel/OK.
  - Cancel/ESC ruft `onCancel` auf, damit das Dropdown auf die zuvor gespeicherte Auswahl zurück rollt. OK liefert `(hour, minute, weekdays)` zurück, der VC schreibt in den aktiven Slot, flippt `reopenMode = .clockTime`, und armed sofort via Manager, sofern `hasSession` — matching der User-Erwartung „Zeit bestätigt = Termin geplant".
- Umsetzung AppDelegate (`xcode/Test/AppDelegate.swift`):
  - `ReopenTimerManager.shared.onFire` wird nach `installShortcutListeners()` verdrahtet: `SessionSlotStore.setActiveIndex(slotIdx)` + `runOnVC { $0.restoreSessionGlobal() }`. `restoreFromDisk()` läuft direkt danach, also nachdem Slot-Store- und Shortcut-Migrationen durch sind und der ViewController-Loaded-Guard aus ISSUE-33 bereits gegriffen hat.
  - Der globale `UserDefaults[waitCheckbox]`-Default wurde aus `defaults.register(defaults:)` entfernt (nur noch ein Kommentar markiert die Stelle). Der Key wird von keinem Code-Pfad mehr gelesen — pre-2.6.0-Installs behalten ihren stale Wert harmlos in UserDefaults.
- Umsetzung Storyboard (`xcode/Test/en.lproj/Main.storyboard`):
  - Checkbox-Titel „Reopen windows in" → **„Reopen this session"** für den neuen per-Slot-Scope.
  - Das `timeDropdown`-Menü im Storyboard bleibt unverändert; `rebuildTimeDropdownForActiveSlot()` ersetzt das Menü sowieso direkt in `viewDidLoad` / bei jedem Slot-Wechsel. Der „At specific time…"-Eintrag wird programmatisch gesetzt, weil der dynamische Header-Eintrag ebenfalls programmatisch rein muss.
- Scope-Entscheidung „nur Clock-Time bekommt Recurrence": klare UX-Intuition („alle 15 min forever" ist eher Bug als Feature) und die Implementierung bleibt berechenbar (`Calendar.nextDate` kann mit `hour/minute/weekday` umgehen, für Duration ist die Rechnung trivial und braucht keine Wochentag-Maske).
- Scope-Entscheidung „autonom für Recurrence, save-getrieben für one-shot": der User-Flow „Preset vorbereiten, Schedule einmal setzen, App kann aus sein" braucht Autonomie — Fire-Date muss über Quits hinweg regeneriert werden können. Für one-shot Clock-Time + Duration gilt weiter „der Save ist der Trigger", weil die semantische Bedeutung („ab jetzt +15 min" oder „genau einmal um 13:30") sonst mehrdeutig würde.
- Dateien: `xcode/Test/SessionSlotStore.swift`, `xcode/Test/ReopenTimerManager.swift` (neu), `xcode/Test/ClockTimeSheetController.swift` (neu), `xcode/Test/ViewController.swift`, `xcode/Test/AppDelegate.swift`, `xcode/Test/en.lproj/Main.storyboard`, `xcode/Later.xcodeproj/project.pbxproj` (zwei neue Swift-Dateien + Build-Phase + MARKETING_VERSION = 2.6.0 / CURRENT_PROJECT_VERSION = 14), `xcode/Test/Info.plist` (2.6.0 / 14), `xcode/build-dmg.sh` (`LATER_VERSION="2.6.0"`).
- Versions-Entscheidung: Minor-Bump (2.5.0 → 2.6.0). Neues User-sichtbares Feature + Datenmodell-Erweiterung + neuer UserDefaults-Key → Patch-Bump wäre zu wenig, Major-Bump wäre zu viel (keine Breaking-Changes am bestehenden Vertrag, alte Blobs decodieren transparent).

### ISSUE-37 · CRIT · FIX — v2.6.1 Hotfix: SIGABRT beim Launch auf macOS 26 (`NSNull` in `UserDefaults[reopen.fireDates]`)
- Beweis: `~/Library/Logs/DiagnosticReports/Later-2026-04-18-133645.ips` (drei reproduzierte Crashes innerhalb von 90 s) — `bundleInfo: CFBundleShortVersionString = 2.6.0, CFBundleVersion = 14`, `exception: EXC_CRASH, signal: SIGABRT`, `asi: "abort() called"`. Faulting-Thread-Backtrace:
  ```
  _CFPrefsValidateValueForKey                         → mutateError (objc_exception)
  -[CFPrefsSource setValues:forKeys:count:…]
  -[_CFXPreferences setValue:forKey:…]
  -[NSUserDefaults(NSUserDefaults) setObject:forKey:]
  ReopenTimerManager.saveFireDates(_:)                 ReopenTimerManager.swift:276
  ReopenTimerManager.init()                            ReopenTimerManager.swift:44
  one-time initialization function for shared          ReopenTimerManager.swift:35
  ViewController.refreshUIForActiveSlot()              ViewController.swift:1154
  ViewController.viewDidLoad()                         ViewController.swift:276
  AppDelegate.applicationDidFinishLaunching(_:)        AppDelegate.swift:136
  ```
- Root-Cause: `ReopenTimerManager.saveFireDates` serialisierte das per-Slot Fire-Date-Array als `[Any]`, wobei „kein Timer armiert" mit `NSNull()` kodiert wurde. `NSNull` ist jedoch **kein zulässiger Property-List-Value**; der CFPrefs-Validator in macOS 26 (Tahoe) wirft beim ersten `defaults.set([NSNull(), NSNull(), …], forKey: "reopen.fireDates")` eine uncaught `NSException` und die Laufzeit terminiert den Prozess via `abort()`. Getriggert wurde das **synchron beim ersten Zugriff auf `ReopenTimerManager.shared`** — und der erste Zugriff fällt direkt in den Launch-Pfad: `AppDelegate.applicationDidFinishLaunching` forciert `vc.view` (siehe ISSUE-33 Kaltstart-Guard), `viewDidLoad` ruft `refreshUIForActiveSlot()`, das wiederum `ReopenTimerManager.shared.fireDate(for:)` fragt. Ergo: App beendet sich, bevor das Popover überhaupt gerendert werden kann.
- Warum das v2.6.0-Testing den Crash verpasst hat: während der initialen Smoke-Tests war `UserDefaults[reopen.fireDates]` noch kein valider plist-Wert, aber das v2.5.0-Upgrade-Pfad hatte den Schlüssel *noch gar nicht* in UserDefaults angelegt. `init()` traf daher den Seed-Branch, schrieb `[NSNull, NSNull, …]`, und der Validator crashte erst beim **nächsten** Launch oder beim ersten `schedule`/`cancel`. In der CI-Build-Kette war nie ein echter Zweit-Launch vorgesehen.
- Fix (nur Persistenzschicht, kein Logik-Change in Schedule/Cancel/Fire):
  - `saveFireDates(_ dates: [Date?])`: schreibt jetzt ein `[Double]` fester Länge 6 (`timeIntervalSince1970`), `0` = „nicht armiert". `Double` ist plist-legal, keine Sonderbehandlung im Validator nötig.
  - `loadFireDates()`: liest primär `[Double]`, fällt defensiv auf das Legacy `[Any]`-Schema (inkl. `Date`, `NSNull`, `NSNumber`, `TimeInterval`) zurück — damit Installs, die v2.6.0 einmal crashend gestartet haben und dabei doch einen legalen Eintrag reingeschrieben bekamen, nicht leer aufwachen.
  - `init()`: ruft zusätzlich `defaults.removeObject(forKey: fireDatesKey)` auf, *bevor* der Seed geschrieben wird, sofern der vorhandene Wert nicht exakt das neue `[Double]`-Schema matcht. Das räumt einen potenziellen `NSNull`-Rest aus v2.6.0 garantiert weg, damit das `set` des Seeds nicht erneut am Validator scheitert.
- Regressionsrisiko minimal: Timer-Logik, Recurrence-Rechnung, UI und AppDelegate-Wiring bleiben unverändert. Einziger semantischer Unterschied: ein stale Fire-Date mit `0`-TimeInterval wird jetzt als „nicht armiert" interpretiert (vorher hätte `Date(timeIntervalSince1970: 0)` = 1970 als vergangenes Feuer gezählt). 1970-Werte konnten nie entstehen, da `schedule` nur `.now + minutes` bzw. `Calendar.nextDate(...)` schreibt.
- Dateien: `xcode/Test/ReopenTimerManager.swift` (Init + `saveFireDates` + `loadFireDates`), `xcode/Test/Info.plist` (2.6.1 / 15), `xcode/Later.xcodeproj/project.pbxproj` (2.6.1 / 15, beide Configs), `xcode/build-dmg.sh` (`LATER_VERSION="2.6.1"`).
- Versions-Entscheidung: Patch-Bump (2.6.0 → 2.6.1). Reiner Hotfix, kein Feature-Change, keine Datenmodell-Erweiterung. Der Hotfix wird bewusst *nicht* mit der geplanten Multi-Timer/Save-Action-Erweiterung zusammengeführt (kommt separat in v2.7.0), damit Nutzer sofort einen start-stabilen Build bekommen ohne zusätzlichen Diff-Scope.

### ISSUE-38 · MED · FIX — v2.6.2: „At specific time…" zeigte keinen Editor (`presentAsSheet` im Popover)
- Symptom: Nutzer wählt im Zeit-Dropdown **„At specific time…"** — es passiert nichts Sichtbares; kein Sheet mit Uhrzeit/Wochentagen.
- Ursache: `ViewController.presentClockTimeSheet()` rief `presentAsSheet(ClockTimeSheetController)` auf. `NSViewController.presentAsSheet(_:)` benötigt eine geeignete Präsentations-Hierarchie; der `ViewController` der Popover-Inhalte sitzt in einem speziellen Fenster-Setup (`NSPopover`). Dort liefert die API häufig **kein sichtbares Sheet** (Apple-Dokumentation: Präsentation hängt vom Parent-Fenster ab). Kurz: gleiches Muster wie bei `ShortcutSettingsController` / `ExcludeSetupEditorController` — die werden bewusst in einem normalen `NSWindow` gehostet, nicht als Sheet vom Popover-VC.
- Fix: `ClockTimeSheetController` wird in ein eigenes, titliertes Fenster (`title: "Reopen schedule"`) gepackt (`NSWindow(contentViewController:)`), `NSApp.activate` + `makeKeyAndOrderFront`. Wiederholter Aufruf bringt ein bereits offenes Fenster nach vorne (`clockTimeSheetWindow`). `ClockTimeSheetController` schließt per `view.window?.close()` statt `dismiss(nil)` (letzteres wirkt bei reiner Window-Hosting nicht zuverlässig), implementiert `NSWindowDelegate.windowWillClose` für den roten Schließen-Button (gleiche Semantik wie **Cancel** → `onCancel` + Dropdown-Rebuild), plus `onWindowClosed` zum Nullen der `ViewController`-Referenz.
- Dateien: `xcode/Test/ViewController.swift`, `xcode/Test/ClockTimeSheetController.swift`, Version 2.6.2 / 16 in `Info.plist`, `project.pbxproj`, `build-dmg.sh`.

### ISSUE-39 · LOW · FEATURE — v2.7.0: Time-Planner-Fenster für alle sechs Slots + gemeinsame Timer-Bearbeitung
- Kontext: Ab v2.6.0 ist der Reopen-Timer pro Slot konfigurierbar, aber die Einstellungen waren nur über das Zeit-Dropdown im Popover je **aktivem** Slot erreichbar — ein Überblick über alle sechs Slots gleichzeitig fehlte. Der Eintrag **„At specific time…"** öffnete zudem nur den Clock-Time-Editor; der Name passte nicht mehr zur erweiterten Nutzung (Duration + Uhrzeit).
- Umsetzung:
  - Neues Fenster **Time planner** (`SessionTimePlannerController`): sechs Zeilen, jeweils Slot-Titel, Statuszeile (`SessionTimerEditing.summary`), `NSPopUpButton` mit Off / 15 / 30 / 60 / 300 Minuten und **Clock time…** (öffnet bestehendes `ClockTimeSheetController`). Beobachtet `Notification.Name.laterSessionTimersChanged` für Live-Refresh.
  - `SessionTimerEditing.swift`: zentrale `applyOff` / `applyDuration` / `applyClockTime`, `summary(forSlotIndex:)`, `postTimersChangedNotification()` — von Popover-Dropdown und Planner gemeinsam genutzt.
  - Zahnrad-Menü und Popover-Zeit-Dropdown: Eintrag **Time planner…** (Tag `7713`, konsistent mit Planner-„Clock"-Pfad), öffnet über `AppDelegate.openTimePlanner`. Dropdown-Menüeinträge ohne per-Item-`action` (Fix für `NSPopUpButton`).
  - Xcode: `SessionTimerEditing.swift` / `SessionTimePlannerController.swift` als `PBXFileReference` ergänzt (vorher nur Build-File + Group — Release-Build konnte die Typen nicht kompilieren).
- Dateien: `xcode/Test/SessionTimerEditing.swift`, `xcode/Test/SessionTimePlannerController.swift`, `xcode/Test/ViewController.swift`, `xcode/Test/AppDelegate.swift`, `xcode/Later.xcodeproj/project.pbxproj`, Version 2.7.0 / 17 in `Info.plist`, `build-dmg.sh`.
- Versions-Entscheidung: Minor-Bump (2.6.2 → 2.7.0). Sichtbares Feature (Planner-Fenster + UX-Umbenennung), kein Breaking Change am Slot-/Timer-Datenmodell.

### ISSUE-40 · MED · FIX — v2.7.1: Time-Planner Save/Cancel, Layout, Draft-Commit
- Symptom: Erste v2.7.0-Version des Time-Planners hatte **keine** Save-/Cancel-Buttons; Änderungen wirkten sofort auf `SessionSlotStore` — inkonsistent zu *Configure shortcuts…* / Erwartungshaltung. Zudem wirkten die Slot-Karten **nicht bündig** (inhaltabhängige Breite im `NSScrollView`).
- Umsetzung:
  - **Draft-Modus:** `draftSlots` in `SessionTimePlannerController`; Änderungen an `NSPopUpButton` und Clock-Sheet nur im Entwurf. **Save** ruft `SessionTimerEditing.commitPlannerDraft(_:)` auf (schreibt alle sechs Slots, reconciliert `ReopenTimerManager` wie die bisherigen `apply*`-Helfer). **Cancel** und Titlebar-Close (`NSWindowDelegate.windowShouldClose` → `orderOut`) verwerfen den Entwurf ohne Persistenz.
  - **Statuszeilen:** `summaryForPlannerDraft` zeigt Live-Countdowns aus `ReopenTimerManager` nur, wenn Draft- und Persistenz-Reopen-Felder übereinstimmen; sonst Hinweis „click Save to apply".
  - **Layout:** `documentView` (`NSStackView`) per `widthAnchor` an `scrollView.contentView` gebunden; Karten als `NSView` mit Layer (Hintergrund, Rand, `cornerRadius`), innerer `NSStackView` mit `edgeInsets`.
- Nicht-Ziele (Dokumentation): **Kein** „Session zur Uhrzeit automatisch speichern“; **kein** zweiter Timer-Typ pro Slot — bleibt Roadmap / spätere Major-Erweiterung.
- Dateien: `xcode/Test/SessionTimePlannerController.swift`, `xcode/Test/SessionTimerEditing.swift`, Version 2.7.1 / 18 in `Info.plist`, `project.pbxproj`, `build-dmg.sh`.

### ISSUE-41 · MED · FIX — v2.7.2: Time-Planner-Fenster kollabiert (kein Slot-Liste sichtbar)
- Symptom: Fenster nur wenige Pixel hoch — nur Einleitungstext + Buttons; die sechs Slot-Zeilen fehlen. Text abgeschnitten.
- Ursache: `NSScrollView` liefert **keine** sinnvolle intrinsische Höhe; die Constraint-Kette setzte die Scroll-Viewport-Höhe praktisch auf 0, `NSWindow` passte die Content-Größe daran an.
- Fix: `scrollView.heightAnchor >= 440`, `root.heightAnchor >= 600`, `preferredContentSize`, `contentMinSize` + `setContentSize` in `AppDelegate.openTimePlanner` und erneut in `SessionTimePlannerController.viewDidAppear`; Intro-Label mit `translatesAutoresizingMaskIntoConstraints = false` und Wrapping-Flags.
- Dateien: `xcode/Test/SessionTimePlannerController.swift`, `xcode/Test/AppDelegate.swift`, Version 2.7.2 / 19 in `Info.plist`, `project.pbxproj`, `build-dmg.sh`.

### ISSUE-42 · MED · FEATURE — v2.7.3: geplanter Speichern-Timer („Save windows for later“) pro Slot
- Kontext: ISSUE-40 / v2.7.1-Changelog hatte dokumentiert, dass Later **keinen** automatischen *Capture* zur Uhrzeit plant — nur Reopen-Timer. Anwendungsfall: Arbeitsbeginn Desktop in einen Slot speichern, Feierabend denselben Slot per Reopen-Timer wiederherstellen; dafür braucht es einen zweiten, unabhängigen Uhrzeit-Plan pro Slot für **Save** (analog Clock-Time + Wochentage wie beim Reopen).
- Umsetzung:
  - `SessionSlotStore.Slot`: Felder `saveScheduleMode` (`.off` / `.clockTime`), `saveClockHour`, `saveClockMinute`, `saveWeekdays`; `Codable`-Defaults für Upgrades.
  - Neuer `ScheduledSaveTimerManager`: persistiert sechs Fire-Dates unter `saveSchedule.fireDates` (`[Double]`, `0` = nicht aktiv), gleiches Muster wie `ReopenTimerManager`.
  - `AppDelegate`: `onSaveFire` setzt den Ziel-Slot aktiv und ruft `saveSessionGlobal()` (wie manueller Save / Quickbar-Save).
  - **Time planner:** zweite Zeile pro Slot **Scheduled save** (Off / Uhrzeit…), eigenes Clock-Sheet („Save schedule“); Scroll-/Mindesthöhen leicht erhöht zweiter Zeile.
  - `SessionTimerEditing.commitPlannerDraft` reconciliert `ScheduledSaveTimerManager` beim Speichern des Planners; Merge/Clear-Slot-Pfade in `ViewController` erhalten Save-Schedule-Felder analog Reopen.
- Dateien: `xcode/Test/SessionSlotStore.swift`, `xcode/Test/ScheduledSaveTimerManager.swift` (neu), `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift`, `xcode/Test/SessionTimerEditing.swift`, `xcode/Test/SessionTimePlannerController.swift`, `xcode/Later.xcodeproj/project.pbxproj`, Version 2.7.3 / 20 in `Info.plist`, `build-dmg.sh`.
- Versions-Entscheidung: Patch-Bump (2.7.2 → 2.7.3), Feature ergänzt v2.7.x ohne Datenmodell-Bruch.

### ISSUE-43 · LOW · FIX — v2.7.4: Time-Planner-Raster + Typo
- Symptom: Sechs Slot-Karten untereinander in **einer** Spalte — Fenster sehr hoch, schmale Karten bei breitem Bildschirm wenig sinnvoll.
- Umsetzung: **2 Spalten × 3 Zeilen** (`NSStackView` pro Zeile, `distribution = .fillEqually`, `alignment = .top`); Root-Breite **720 pt**, `AppDelegate.openTimePlanner` gleiche Mindestbreite/-höhe. Kürzere Sektions-Labels (**Restore**, **Scheduled save**) mit Tooltips; feinere Innenabstände und `setCustomSpacing` zwischen Restore- und Save-Block; Intro-Text gekürzt.
- Dateien: `xcode/Test/SessionTimePlannerController.swift`, `xcode/Test/AppDelegate.swift`, Version 2.7.4 / 21 in `Info.plist`, `project.pbxproj`, `build-dmg.sh`.
- Versions-Entscheidung: Patch-Bump (2.7.3 → 2.7.4), reine UX-Anpassung.

### ISSUE-44 · LOW · DOC/FIX — v2.7.5: Popover-Versionsanzeige + Tracker-Pflege
- Symptom: Im Popover neben dem Titel „Later“ stand fest **v2.1** im Storyboard — driftet bei jedem Release.
- Umsetzung: `NSTextField` per IBOutlet `versionLabel`; `ViewController.applyVersionLabelFromBundle()` setzt `v<CFBundleShortVersionString> (<CFBundleVersion>)` aus `Bundle.main.infoDictionary`. Storyboard-Platzhalter geleert.
- Tracker: SEC-Tabelle **SEC-01** klärt Fork-vs.-Original (Version-Pins in `Package.resolved`); Sicherheits-Review **v2.6.0**-Absatz zu `reopen.fireDates` auf **v2.6.1+ `[Double]`** korrigiert (statt veralteter `Date`/`NSNull`-Formulierung).
- Dateien: `xcode/Test/ViewController.swift`, `xcode/Test/en.lproj/Main.storyboard`, `ISSUES.md`, Version 2.7.5 / 22 in `Info.plist`, `project.pbxproj`, `build-dmg.sh`, `README.md`.

### ISSUE-35 · LOW · FEATURE — v2.5.0: konfigurierbare globale Shortcuts
- Kontext: Bis einschließlich v2.4.3 waren `⌘⇧L` (Save active) und `⌘⇧R` (Restore active) in `ViewController` hart verdrahtet (`HotKey` 0.2.0, Initialisierung in `viewDidLoad`). Der einzige UI-Schalter war der Zahnrad-Eintrag **„Disable all shortcuts"**, der lediglich die beiden `HotKey`-Instanzen `nil`te — es gab keine Möglichkeit, die Kombinationen zu ändern oder neue Slots darauf zu legen. Die Frage „was genau deaktiviert der Toggle, wenn ich nie einen Shortcut angelegt habe?" war berechtigt.
- Umsetzung:
  - Neue SwiftPM-Dependency [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) auf `upToNextMajorVersion(2.3.0)` gepinnt (tatsächlich resolved 2.4.0, aktueller Stand beim Build). Die Bibliothek kapselt Global-Key-Handling, Persistenz (`UserDefaults_KeyboardShortcuts_<Name>`) und stellt eine fertige `RecorderCocoa`-Komponente. Keine neue Angriffsfläche gegenüber SEC-05: gespeichert werden ausschließlich Shortcut-Kombinationen, keine Executable-Pfade.
  - Neue Datei `xcode/Test/Shortcuts.swift` deklariert acht `KeyboardShortcuts.Name`-Einträge: `saveActiveSession` (Default `⌘⇧L`), `restoreActiveSession` (Default `⌘⇧R`) und `restoreSlot1…6` (keine Defaults — bewusst, damit keine ungewollten Kollisionen mit System-Shortcuts oder anderen Apps passieren). Die Defaults matchen die v2.4.x-Hardcodes, damit Upgrades ohne Shortcut-Verlust laufen.
  - Neue Datei `xcode/Test/ShortcutSettingsController.swift`: programmatischer `NSViewController` (keine Storyboard-Kopplung), baut einen `NSStackView` mit Header-Label und einer Zeile pro Shortcut. Slot-Zeilen lesen `SessionSlotStore.slot(at:)` und zeigen entweder `Restore Slot N (<sessionName>)` oder `Restore Slot N (empty)` — so weiß der User, welchen Slot er gerade zuweist.
  - `AppDelegate` bekommt drei neue Methoden: `installShortcutListeners()` (wird einmal beim Start aufgerufen, registriert `onKeyDown` für alle acht Namen), `applyShortcutMasterToggle()` (enable/disable-All, respektiert den `switchKey`-Default) und `openShortcutSettings(_:)` (lazy `NSWindow` mit `ShortcutSettingsController`, `isReleasedWhenClosed = false`, vor Anzeige `NSApp.activate(ignoringOtherApps: true)` für den `.accessory`-Fall).
  - Neuer privater Helper `runOnVC(_:)` in `AppDelegate` ersetzt das duplizierte Kaltstart-Pattern aus `quickRestoreSlot` und `quickSaveSlot`: er erzwingt `_ = vc.view` und führt den Body aus — sodass Shortcut-Handler vor dem ersten Popover-Öffnen sicher auf IBOutlets zugreifen können.
  - `ViewController`: `HotKey`-Import, `closeKey`/`restoreKey`-Properties und `switchKey()`-Implementation entfernt. Das alte `checkKey`-Menuitem wurde durch zwei neue Einträge ersetzt: `menuItemConfigureShortcuts` (öffnet das Settings-Fenster über `AppDelegate.openShortcutSettings`) und `menuItemEnableShortcuts` (Master-Toggle mit Checkmark). Letzterer schreibt weiter in `UserDefaults[switchKey]` mit invertierter Polarität (`switchKey == true` bedeutet _disabled_), damit Upgrades v2.4.x → v2.5.0 die vorherige Wahl nicht verlieren.
  - Migration: neuer One-Shot-Flag `shortcutsV2Migrated`. Die v2.5.0-Migration setzt den Flag beim ersten Start auf `true` — kein aktiver Flip der `switchKey`-Polarität nötig, weil die Default-Seeding bereits durch `KeyboardShortcuts` selbst läuft. Der Flag ist ein Platzhalter für künftige Folge-Migrationen an denselben Keys.
  - Nachgeliefert (v2.5.0 Follow-up): expliziter **Save / Cancel**-Button am unteren Rand des Sheets. Die `KeyboardShortcuts`-Recorder persistieren jede Eingabe sofort in `UserDefaults` — eine klassische Transaktions-Semantik existiert upstream nicht. Daher snapshotted der Controller in `viewWillAppear` alle Shortcuts via `KeyboardShortcuts.getShortcut(for:)` und spielt sie in Cancel bzw. in `windowShouldClose(_:)` per `setShortcut(_:for:)` zurück. Die Titlebar-X wird über das `NSWindowDelegate`-Protokoll abgefangen: `windowShouldClose` gibt `false` zurück und macht `orderOut(nil)`, damit die Window-Instanz am Leben bleibt. Hintergrund: ohne diesen Abfang beendete ein Klick auf den roten X-Button in `.accessory`-Launches (Dock-Icon aus) überraschend die gesamte App, weil das einzige sichtbare Fenster verschwand und AppKit den Prozess aufräumte.
- Dateien: `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift`, `xcode/Test/Shortcuts.swift` (neu), `xcode/Test/ShortcutSettingsController.swift` (neu), `xcode/Later.xcodeproj/project.pbxproj`.
- Scope-Entscheidung: 2 Globals + 6 Slot-Restores = 8 Shortcuts. Save pro Slot wurde bewusst weggelassen — der v2.4.3-Quickbar-Save deckt das Panik-Szenario bereits ab, und doppelt so viele Recorder-Zeilen hätten die Settings-Sheet-Lesbarkeit gekillt.
- `HotKey 0.2.0` SwiftPM-Entry bleibt zunächst noch als Package-Referenz stehen, damit dieser Commit reviewbar bleibt; der Target-Link ist bereits ersetzt. Ein Follow-up-Commit kann die Dependency später vollständig entfernen.
- Versions-Entscheidung: Minor-Bump (2.4.3 → 2.5.0). Die Rework am Gear-Menü („Disable all shortcuts" ist weg, zwei neue Einträge) plus neue Dependency rechtfertigen keinen Patch-Bump mehr, aber auch keinen Major-Bump (keine Breaking-Changes an Public-API / `UserDefaults`-Keys).

### ISSUE-34 · LOW · FEATURE — v2.4.3: Save-Submenu in der Rechtsklick-Quickleiste
- Kontext: Die v2.4.2-Quickleiste konnte nur Sessions *wiederherstellen*. Das typische „Chef kommt rein, Desktop muss sofort sauber sein"-Szenario erforderte trotzdem das Popover, weil der grüne Save-Button dort lebt. Zwei Klicks zu viel für eine Panik-Geste.
- Umsetzung:
  - `showQuickMenu()` bekommt zwischen der Restore-Liste und „Open Later…" einen neuen Eintrag **„Save current session to…"** mit 6-Slot-Submenu.
  - Submenu-Titel: `Slot N — empty` für leere Slots, `Slot N — overwrite <sessionName>` für belegte — keine Confirm-Dialog-Unterbrechung, die Bezeichnung ist der explizite Hinweis.
  - Aktiver Slot bekommt auch im Save-Submenu ein Häkchen, konsistent mit der Restore-Liste.
  - Neue `@objc private func quickSaveSlot(_:)` setzt `SessionSlotStore.setActiveIndex(tag)`, erzwingt dieselbe `_ = vc.view`-Idempotenz wie `quickRestoreSlot(_:)` (Kaltstart-Schutz, `saveSessionGlobal()` referenziert `button`, `noSessionLabel` usw.) und ruft `vc.saveSessionGlobal()`. Das löst dieselbe Screenshot + Exclude/Close-Pipeline aus wie der grüne Button im Popover — inklusive `NSApp.setActivationPolicy(.regular)`-Dance aus ISSUE-23.
  - Es wird bewusst kein Confirm-Dialog eingebaut: die Session lässt sich mit dem neuen 6-Slot-Backup trivial wieder ersetzen, und ein Blockier-Dialog würde den Panik-Use-Case kaputtmachen.
- Datei: `xcode/Test/AppDelegate.swift`.
- Versions-Entscheidung: Patch-Bump (2.4.2 → 2.4.3), additives Feature aufbauend auf der v2.4.2-Quickleiste.

### ISSUE-33 · LOW · FEATURE — v2.4.2: Session-Quickleiste via Rechtsklick aufs Menüleisten-Icon
- Kontext: Bis v2.4.1 war die einzige Möglichkeit, eine Session wiederherzustellen, das Popover zu öffnen (Linksklick / Hotkey / Dock-Icon), den richtigen Slot auszuwählen und den grünen Restore-Button zu drücken. Für reine „Preset-Nutzer" (Work/Home/Coding) ist das drei Klicks zu viel.
- Umsetzung:
  - `NSStatusItem.button` bekommt in `applicationWillFinishLaunching` zusätzlich `sendAction(on: [.leftMouseUp, .rightMouseUp])` — beide Event-Typen laufen jetzt durch `togglePopover(_:)`.
  - `togglePopover(_:)` sniffelt `NSApp.currentEvent`: `rightMouseUp` oder `leftMouseUp` + `.control` → neuer `showQuickMenu()`-Pfad; sonst die bisherige Show/Hide-Logik (jetzt ausgelagert in `togglePopoverInternal(_:)`).
  - `showQuickMenu()` baut bei jedem Aufruf ein frisches `NSMenu`: disabled Header „Sessions", sechs Slot-Einträge mit Titeln `Slot N — <sessionName>` (bzw. `Slot N — empty`), aktiver Slot bekommt `state = .on`, leere Slots `isEnabled = false`. Unten Separator → „Open Later…" (öffnet/schließt das Popover via `togglePopoverFromMenu`), Separator → Quit. Anker ist der Status-Item-Button, damit das Menü direkt darunter erscheint.
  - `quickRestoreSlot(_:)` setzt den aktiven Slot via `SessionSlotStore.setActiveIndex(_:)` und ruft `vc.restoreSessionGlobal()` auf der `ViewController`-Instanz auf. Vorher wird `_ = vc.view` erzwungen, weil `restoreSessionGlobal()` auf IBOutlets (`closeApps`, …) zugreift — bei einem Kaltstart, in dem das Popover noch nie geöffnet wurde, wäre das sonst ein Crash. `loadViewIfNeeded()` wäre die sauberere API, ist aber macOS 14+; `vc.view` tut dasselbe und ist seit macOS 10.10 verfügbar.
  - Fallback: Ist das Status-Item unsichtbar (Bartender/Hidden Bar-Szenario), fällt der Rechtsklick auf den bestehenden Popover-Fallback-Anker zurück — ein `NSMenu` ohne sichtbares Ankerfenster könnte sonst an der Mausposition „verloren" wirken.
- Dateien: `xcode/Test/AppDelegate.swift`.
- Versions-Entscheidung: Patch-Bump (2.4.1 → 2.4.2), rein additives Feature, keine Verhaltensänderung für den bisherigen Linksklick-Pfad.

### ISSUE-32 · LOW · FEATURE — v2.4.1: Liquid-Glass-Opt-out im Zahnrad-Menü
- Kontext: Mit v2.4 adoptiert das Popover auf macOS 26+ automatisch Liquid Glass. Nutzer, denen die neue Transluzenz zu subtil ist oder die vor hellem Wallpaper schlecht lesbar bleibt, brauchen einen direkten Opt-out.
- Umsetzung:
  - Neuer `UserDefaults`-Key `useLiquidGlass` (Default `true`), registriert zusammen mit den anderen Standards in `AppDelegate.applicationDidFinishLaunching`.
  - Neuer Menüeintrag „Use Liquid Glass (Tahoe)" in `setUpMenu` unterhalb der Dock-/Menüleisten-Toggles. Nur unter `#available(macOS 26.0, *)` eingefügt, damit pre-Tahoe-Builds keinen toten Eintrag zeigen.
  - `toggleLiquidGlassFromMenu(_:)` flippt den Default, aktualisiert den Menü-State und ruft sowohl `applyLiquidGlassIfAvailable()` + `applyExcludeSetupRowStyle()` (NSBox-Füllungen und Setup-Zeilen-Farben) als auch den neuen `AppDelegate.reapplyPopoverAppearance()` (Popover-Backdrop + `NSAppearance`) live auf — ohne Popover-Schließen.
  - Aus dem v2.4 ursprünglich inline in `showPopover` erledigten Branch wurde der neue `reapplyPopoverAppearance()`; `showPopover` delegiert jetzt dorthin. Wenn Liquid Glass aktiv ist, werden `popoverView.backgroundColor = nil` und `popoverView.appearance = nil` gesetzt, sodass frühere Overrides bei einem Live-Toggle wieder entfernt werden.
  - `legacyBoxFillColor` in `ViewController` hält die Storyboard-Farbe (display-P3 ~0.184) als Konstante, damit der Off-Modus byte-identisch zum alten Look aussieht.
- Dateien: `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift`.
- Versions-Entscheidung: Patch-Bump (2.4 → 2.4.1) — kleiner Folge-Tweak direkt an der v2.4-Neuerung, kein anderes Feature geändert.

### ISSUE-31 · LOW · FEATURE — v2.4: Liquid-Glass-Opt-in auf macOS 26 (Tahoe)
- Kontext: Das Binary wird mit Xcode 26.4.1 gegen das macOS 26.4 SDK gelinkt; Tahoe würde das Popover damit automatisch mit dem neuen Liquid-Glass-Material unterlegen. Drei Stellen haben das in v2.3.1 aber noch verhindert:
  1. `AppDelegate.showPopover` setzte `popoverView.backgroundColor = #colorLiteral(...)` und erzwang `popoverView.appearance = NSAppearance(named: .aqua)`, was die Glass-Schicht komplett mit einem opaken hellen Panel überdeckte.
  2. Die beiden `NSBox`es im Storyboard (`box` = Session-Preview, id `MPy-SW-b88`; `optionsBox` = Options-Bereich, id `9VD-Ls-6F0`) tragen einen hartcodierten dunklen `fillColor`, wodurch selbst bei durchlässigem Popover nichts vom Glass durchscheint.
  3. `applyExcludeSetupRowStyle()` erzwang `NSAppearance(named: .darkAqua)` auf der Setup-Zeile und setzte feste hellweiße Text-Farben, was auf adaptivem Glass (hell/dunkel) nicht mehr paßt.
- Fix: Alle drei Stellen werden ab macOS 26 per `#available(macOS 26.0, *)` umgangen. Deployment-Target bleibt 13.0, das alte dunkle Look & Feel wird für 13.0–15.x exakt so weiter ausgeliefert (inkl. erzwungenem `.aqua` und darkAqua-Setup-Zeile). Auf Tahoe+ wird das Popover durchsichtig (`box.fillColor = .clear`, `optionsBox.fillColor = .clear`), die Setup-Zeile nutzt `NSColor.labelColor`. Kein neuer Default, kein Storyboard-Override — das alte Aussehen pre-Tahoe ist byte-identisch.
- Dateien: `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift`.
- Nicht umgesetzt (bewußt, Scope „medium"): SlotButton-Eigenzeichnung und erzwungene dunkle Farben in einigen Labels bleiben. Für einen vollen Redesign (`NSVisualEffectView`-Backdrops, semantische Farben überall, SlotButton ohne Layer-Tint) wird ein Folge-Ticket aufgemacht, wenn der Look auf Tahoe evaluiert ist.

### ISSUE-30 · MED · FIX — v2.1: Dock- und Menüleisten-Sichtbarkeit + Popover-Fallback
- Anforderung: Nutzer soll **Dock-Icon** und **Menüleisten-Icon** unabhängig ein-/ausschalten können (`UserDefaults`: `showDockIcon`, `showMenuBarIcon`; Standard jeweils an). Mindestens eines muss aktiv bleiben, sonst nur noch globaler Hotkey (Hinweisdialog).
- Umsetzung:
  - **Steuerung:** `AppDelegate.applyAppearanceSettings()` setzt `NSApp.setActivationPolicy(.regular)` wenn Dock sichtbar, sonst `.accessory`; `statusItem.isVisible` für das Menüleisten-Icon.
  - **UI:** Die beiden Optionen liegen im **Zahnrad-Menü** (`NSMenuItem` mit `state`), nicht im Popover — damit bleiben die festen Storyboard-Höhen für „Save“/Restore erhalten.
  - **Popover-Anker:** Wenn das Status-Item nicht sichtbar ist oder außerhalb des sichtbaren Bildschirms liegt, zeigt `showPopover` das Popover an einem **kleinen Ankerfenster** oben mittig am Hauptdisplay (`fallbackAnchorWindow`), statt nur am (unsichtbaren) Button-Frame zu scheitern.
- Dateien: `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift` (`setUpMenu`, `syncAppearanceMenuItemsFromDefaults`).

---

## Sicherheits-spezifische Findings

| ID | Thema | Schwere |
|---|---|---|
| SEC-01 | Branch-Pinning von SwiftPM-Deps — **im Original-Repo** HIGH. **Dieses Fork:** alle SPM-Deps über **Version-Pins** (`HotKey` 0.2.0, `KeyboardShortcuts` 2.4.0, `LaunchAtLogin-Modern` 1.1.0 in `Package.resolved`), kein `branch=`. | FIX (Fork) |
| SEC-02 | `com.apple.security.cs.allow-jit` ohne Bedarf (kein eigener Interpreter / JIT). Öffnet R+W+X-Speicher. | MED |
| SEC-03 | Keine Sandbox (`com.apple.security.app-sandbox`) — App hat Vollzugriff auf Documents, Running-Apps, Prozess­start via `Process()`. Bei App-Store-Distribution nicht abnahmefähig. | MED (für Self-Distribution akzeptabel) |
| SEC-04 | Screenshot wird als `screenshot.jpg` in `~/Documents/` abgelegt — potenziell sensitive Daten in geteiltem Ordner; andere Apps können mitlesen. | MED |
| SEC-05 | `defaults.set(array, forKey: "apps")` speichert Executable-URLs ungeprüft (String). Bei Manipulation der plist könnte ein Angreifer beim nächsten „Restore" per `Process().run()` beliebige Binaries ausführen. | HIGH |
| SEC-06 | Keine Notarisierung / ad-hoc Signatur (ISSUE-01). | HIGH |

**Fixes (Sicherheit):**
- SEC-01 → Tag-Pinning in `project.pbxproj` + `Package.resolved` (Stand v2.7.5: keine Branch-Pins).
- SEC-02 → siehe ISSUE-16 (Entitlement entfernen).
- SEC-04 → Screenshot nach `Application Support/Later/` umziehen, `FileManager` mit `withIntermediateDirectories`.
- SEC-05 → Bundle-Identifier + Bundle-URL statt Executable-URL speichern, beim Restore via `NSWorkspace` auflösen (ISSUE-11 kombiniert den Fix).

### Sicherheits-Review v2.2 (neue Stores)

Die v2.2-Änderungen wurden separat auf Angriffsflächen geprüft. Stand: keine neuen High/Crit-Findings.

| Komponente | Review | Ergebnis |
|---|---|---|
| `SessionSlotStore.Slot` (Codable, 6 JSON-Blobs in `UserDefaults`) | Beim Decode wird die Array-Länge gegen `slotCount` validiert; Einzelinhalte sind reine Metadata (Datum, Anzeigename, Bundle-IDs, Legacy-URL-Strings). | OK — Exekution läuft weiterhin ausschließlich über `NSWorkspace.openApplication(at:)` mit `.app`-Filter, SEC-05 bleibt gefixt. |
| `ExcludeSetupMode.init?(rawValue:)` | Validiert Slot-Index gegen `ExcludeSetupStore.slotCount` (0..<4). | OK — manipulierte Plist-Werte fallen auf `.all`. |
| `ExcludeSetupStore.mode(forSessionSlot:)` / Per-Slot-Persistenz | String-Array mit fester Länge (`SessionSlotStore.slotCount`). Bei Längen-Mismatch wird reseeded. | OK. |
| `SessionSlotStore.screenshotFileName(for:)` | Dateiname wird aus einem intern kontrollierten `Int` (0..<6) gebildet. Kein User-Input. | OK — kein Pfad-Traversal. |
| `SessionSlotStore.migrateIfNeeded()` legacy-Screenshot-Move | Quelle/Ziel liegen beide unter `Application Support/<bundleID>/`, `moveItem` nur wenn Quelle existiert und Ziel fehlt. | OK. |

Keine neuen SEC-Einträge notwendig. Bestehende Einträge SEC-04/05 gelten fortgeführt für die Multi-Slot-Daten.

### Sicherheits-Review v2.3 (Preset-Restore)

Die Umstellung auf wiederverwendbare Presets (ISSUE-27/28) ändert weder die Persistenz­form noch die Exekutions-Pfade — App-Start läuft weiterhin über `NSWorkspace.openApplication(at:)` mit Bundle-ID-Filter (SEC-05), und die Close-Schleife respektiert unverändert `shouldInclude`, `com.apple.Terminal` und `isSystemApp`. Neu hinzugekommen ist lediglich der Diff-Filter gegen die Ziel-Session (`targetBundleIDs`/`targetNames`), der die Menge beendeter Apps *verkleinert*. Keine neuen SEC-Findings.

### Sicherheits-Review v2.5.0 (konfigurierbare Shortcuts)

Die neue Dependency `KeyboardShortcuts` 2.4.0 speichert Shortcut-Kombinationen ausschließlich als `UserDefaults`-Keys unter dem Prefix `KeyboardShortcuts_` (Modifier-Maske + Keycode, kein String-Eval). Die Handler in `AppDelegate.installShortcutListeners()` rufen ausschließlich bereits bestehende `ViewController`-Methoden (`saveSessionGlobal()`, `restoreSessionGlobal()`) mit einem validierten Slot-Index auf — keine neue Exekutions-Angriffsfläche gegenüber SEC-05. Das neue `shortcutWindow` wird über `NSWindow.contentViewController` erzeugt und ist `isReleasedWhenClosed = false`; keine KVO-/IPC-Flächen. SEC-01 bleibt gefixt (Tag-Pinning mit `upToNextMajorVersion`).

### Sicherheits-Review v2.6.0 (per-Slot Reopen-Timer)

Die neuen Felder im `Slot`-Struct sind reine Primitivtypen (`String` raw für den Enum-Mode, `Int` für Zeit, `[Int]` für Weekdays). `reopenWeekdays` wird bei der Berechnung per `(1...7).contains(day)` gefiltert, `reopenClockHour`/`Minute` beim Anwenden auf `0...23` / `0...59` geklemmt — ein manipulierter Plist-Blob kann keine negative Wartezeit, keine ungültige Wochentags-Zahl, keinen Out-of-Range-Hour-Wert in die `Calendar`-API füttern. `UserDefaults[reopen.fireDates]` enthält seit **v2.6.1** ausschließlich `[Double]`-Zeitstempel (`0` = kein aktiver Timer); v2.6.0 hatte fälschlich `NSNull` in der Liste (Hotfix ISSUE-37). Kein String-Eval / kein Executable-Pfad (SEC-05 bleibt gefixt). Der Feuer-Pfad routet weiterhin ausschließlich über `restoreSessionGlobal()` → `NSWorkspace.openApplication(at:)` mit Bundle-ID-Filter — keine neue Angriffsfläche im App-Start-Pipeline. `Timer` + `RunLoop.main.add(_:forMode:)` laufen in-process, kein IPC/XPC. Kein neues Entitlement/TCC-Scope.

---

## Build-Anleitung (saubere Distribution für aktuelles macOS)

1. Xcode ≥ 15 installieren (nicht nur Command Line Tools).
2. Repo öffnen: `open later/xcode/Later.xcworkspace`.
3. `Signing & Capabilities` → Team auswählen.
4. `Product → Archive` → im Organizer „Distribute App → Developer ID → Upload to Notarize".
5. Nach Notarisierung: DMG neu erstellen (`hdiutil create -fs HFS+ -volname Later -srcfolder Later.app Later.dmg`) und stapeln (`xcrun stapler staple Later.dmg`).

Ohne Apple-Developer-ID (99 USD/Jahr) ist eine saubere Auslieferung nicht möglich — der Nutzer muss die App dann wie in ISSUE-01 beschrieben manuell freigeben.

---

## Status der Abarbeitung

Stand des aktuellen Commits in diesem Repo:

| Issue | Status | Dateien |
|---|---|---|
| ISSUE-01 | DOC (nicht fixbar ohne Developer-ID) | — |
| ISSUE-02 | FIX (ScreenCaptureKit + legacy fallback, keine Force-Unwraps) | `xcode/Test/ViewController.swift` |
| ISSUE-03 | FIX (LaunchAtLogin-Modern 1.1.0 pinned, Autostart nicht mehr erzwungen) | `xcode/Later.xcodeproj/project.pbxproj`, `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift` |
| ISSUE-04 | FIX (HotKey 0.2.0 pinned) | `xcode/Later.xcodeproj/project.pbxproj`, beide `Package.resolved` |
| ISSUE-05 | FIX (`ATSApplicationFontsPath` gesetzt) | `xcode/Test/Info.plist` |
| ISSUE-06 | FIX (`LSUIElement = false` + `.accessory`→`.regular` flip) | `xcode/Test/Info.plist`, `xcode/Test/AppDelegate.swift` |
| ISSUE-07 | FIX (`isSystemApp` via Bundle-ID) | `xcode/Test/ViewController.swift` |
| ISSUE-08 | FIX (alle `!` durch sicheres Unwrapping ersetzt) | `xcode/Test/*.swift`, `xcode/EventMonitor.swift` |
| ISSUE-09 | FIX (CGDirectDisplayID-Pointer entfällt, ScreenCaptureKit-Pfad) | `xcode/Test/ViewController.swift` |
| ISSUE-10 | FIX (ScreenCaptureKit-Pfad; Legacy-Pfad ohne Schleife) | `xcode/Test/ViewController.swift` |
| ISSUE-11 | FIX (`NSWorkspace.openApplication(at:)` + Bundle-ID-Lookup) | `xcode/Test/ViewController.swift` |
| ISSUE-12 | FIX (`guard let self`) | `xcode/Test/ViewController.swift` |
| ISSUE-13 | FIX (`"q"` lowercase) | `xcode/Test/ViewController.swift` |
| ISSUE-14 | FIX (`UserDefaults.register(defaults:)`) | `xcode/Test/AppDelegate.swift` |
| ISSUE-15 | FIX (duplicate `statusItem`/`popoverView` entfernt) | `xcode/Test/ViewController.swift` |
| ISSUE-16 | FIX (`NSScreenCaptureUsageDescription`, `CFBundleVersion`, `allow-jit` entfernt) | `xcode/Test/Info.plist`, `xcode/Test/Test.entitlements` |
| ISSUE-17 | FIX (Link auf Repo umgebogen) | `xcode/Test/ViewController.swift` |
| ISSUE-18 | FIX (nur Log statt `fatalError`) | `xcode/Test/AppDelegate.swift` |
| ISSUE-19 | FIX (keepWindowsOpen + closeApps respektieren `isSystemApp`) | `xcode/Test/ViewController.swift` |
| ISSUE-20 | FIX (Default 15 min statt 10 s) | `xcode/Test/ViewController.swift` |
| ISSUE-21 | FIX (Index-Guarding beim Restore) | `xcode/Test/ViewController.swift` |
| ISSUE-22 | FIX (`MACOSX_DEPLOYMENT_TARGET = 13.0`) | `xcode/Later.xcodeproj/project.pbxproj` |
| ISSUE-23 | FIX (lazy StatusItem, Accessory→Regular-Flip, 18×18 Icon-Resize, Dock-Klick öffnet Popover) | `xcode/Test/AppDelegate.swift`, `xcode/Test/Info.plist` |
| ISSUE-24 | FIX (v2.2: englische Register-Defaults für `excludeSetup.displayNames`) | `xcode/Test/AppDelegate.swift` |
| ISSUE-25 | FIX (v2.2: Store-Migrationen vor erstem UI-Refresh) | `xcode/Test/ViewController.swift` |
| ISSUE-26 | FIX (v2.2: Placeholder-Toggle lässt `timeWrapper` in Ruhe) | `xcode/Test/ViewController.swift` |
| ISSUE-27 | FIX (v2.3: Restore lässt den Slot erhalten, Guard gegen leeren Slot) | `xcode/Test/ViewController.swift` |
| ISSUE-28 | FIX (v2.3: Close-Schleife nimmt Session-Apps aus, Checkbox umbenannt) | `xcode/Test/ViewController.swift`, `xcode/Test/en.lproj/Main.storyboard` |
| ISSUE-29 | FIX (v2.3.1: `activate()` ignoriert terminierende Apps, Relaunch klappt wieder) | `xcode/Test/ViewController.swift` |
| ISSUE-30 | FIX (v2.1: Dock/Menüleiste per Zahnrad, `applyAppearanceSettings`, Popover-Fallback-Anker) | `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift` |
| ISSUE-31 | FEATURE (v2.4: Liquid-Glass-Opt-in auf macOS 26, runtime-gated, pre-Tahoe unverändert) | `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift` |
| ISSUE-32 | FEATURE (v2.4.1: Zahnrad-Menü-Toggle zum Deaktivieren von Liquid Glass, Live-Update) | `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift` |
| ISSUE-33 | FEATURE (v2.4.2: Rechtsklick-Quickleiste auf dem Menüleisten-Icon, Ein-Klick-Restore über `NSMenu`) | `xcode/Test/AppDelegate.swift` |
| ISSUE-34 | FEATURE (v2.4.3: Save-Submenu in der Rechtsklick-Quickleiste, Slot-Auswahl + `saveSessionGlobal()`) | `xcode/Test/AppDelegate.swift` |
| ISSUE-35 | FEATURE (v2.5.0: konfigurierbare globale Shortcuts via `KeyboardShortcuts` 2.4.0, 2 Globals + 6 Slot-Restores, Settings-Sheet im Zahnrad-Menü, `HotKey` aus dem Code entfernt) | `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift`, `xcode/Test/Shortcuts.swift`, `xcode/Test/ShortcutSettingsController.swift`, `xcode/Later.xcodeproj/project.pbxproj` |
| ISSUE-36 | FEATURE (v2.6.0: per-Slot-Reopen-Timer mit Duration + Clock-Time + Weekday-Recurrence, `ReopenTimerManager` als Single-Source-of-Truth, Fire-Dates persistiert in `UserDefaults[reopen.fireDates]`, SlotButton-Badges, Clock-Time-Sheet) | `xcode/Test/SessionSlotStore.swift`, `xcode/Test/ReopenTimerManager.swift`, `xcode/Test/ClockTimeSheetController.swift`, `xcode/Test/ViewController.swift`, `xcode/Test/AppDelegate.swift`, `xcode/Test/en.lproj/Main.storyboard`, `xcode/Later.xcodeproj/project.pbxproj` |
| ISSUE-37 | FIX (v2.6.1 Hotfix: `NSNull` aus `UserDefaults[reopen.fireDates]` raus, `[Double]`-Schema mit `0` als „not armed", Init räumt Legacy-Payloads weg — App startet wieder auf macOS 26) | `xcode/Test/ReopenTimerManager.swift`, `xcode/Test/Info.plist`, `xcode/Later.xcodeproj/project.pbxproj`, `xcode/build-dmg.sh` |
| ISSUE-38 | FIX (v2.6.2: Clock-Time-Editor als eigenes Fenster statt `presentAsSheet` im Popover — „At specific time…" sichtbar) | `xcode/Test/ViewController.swift`, `xcode/Test/ClockTimeSheetController.swift`, `xcode/Test/Info.plist`, `xcode/Later.xcodeproj/project.pbxproj`, `xcode/build-dmg.sh` |
| ISSUE-39 | FEATURE (v2.7.0: Time-Planner-Fenster für alle Slots, `SessionTimerEditing`, Umbenennung „Time planner…", `PBXFileReference`-Fix für neue Swift-Dateien) | `xcode/Test/SessionTimerEditing.swift`, `xcode/Test/SessionTimePlannerController.swift`, `xcode/Test/ViewController.swift`, `xcode/Test/AppDelegate.swift`, `xcode/Later.xcodeproj/project.pbxproj`, `xcode/Test/Info.plist`, `xcode/build-dmg.sh` |
| ISSUE-40 | FIX (v2.7.1: Time-Planner Save/Cancel + Draft-Commit, Scroll-Breiten-Fix, `summaryForPlannerDraft`, `commitPlannerDraft`) | `xcode/Test/SessionTimePlannerController.swift`, `xcode/Test/SessionTimerEditing.swift`, `xcode/Test/Info.plist`, `xcode/Later.xcodeproj/project.pbxproj`, `xcode/build-dmg.sh` |
| ISSUE-41 | FIX (v2.7.2: Time-Planner Mindesthöhe / `contentMinSize` — Fenster kollabierte ohne sichtbare Slot-Liste) | `xcode/Test/SessionTimePlannerController.swift`, `xcode/Test/AppDelegate.swift`, `xcode/Test/Info.plist`, `xcode/Later.xcodeproj/project.pbxproj`, `xcode/build-dmg.sh` |
| ISSUE-42 | FEATURE (v2.7.3: geplanter Speichern-Timer pro Slot, `ScheduledSaveTimerManager`, zweite Planner-Zeile) | `xcode/Test/SessionSlotStore.swift`, `xcode/Test/ScheduledSaveTimerManager.swift`, `xcode/Test/AppDelegate.swift`, `xcode/Test/ViewController.swift`, `xcode/Test/SessionTimerEditing.swift`, `xcode/Test/SessionTimePlannerController.swift`, `xcode/Later.xcodeproj/project.pbxproj`, `xcode/Test/Info.plist`, `xcode/build-dmg.sh` |
| ISSUE-43 | FIX (v2.7.4: Time-Planner 2×3-Raster, Fensterbreite 720 pt, kürzere Labels + Tooltips) | `xcode/Test/SessionTimePlannerController.swift`, `xcode/Test/AppDelegate.swift`, `xcode/Test/Info.plist`, `xcode/Later.xcodeproj/project.pbxproj`, `xcode/build-dmg.sh` |
| ISSUE-44 | FIX/DOC (v2.7.5: Popover-Version aus Bundle; ISSUES SEC-01 + v2.6.0-Review-Text aktualisiert) | `xcode/Test/ViewController.swift`, `xcode/Test/en.lproj/Main.storyboard`, `ISSUES.md`, `README.md`, `xcode/Test/Info.plist`, `xcode/Later.xcodeproj/project.pbxproj`, `xcode/build-dmg.sh` |
| SEC-01 | FIX (Fork: SPM-Version-Pins, kein Branch-Pinning) | `Package.resolved`, siehe ISSUE-03/04 |
| SEC-02 | FIX (`allow-jit` entfernt) | `xcode/Test/Test.entitlements` |
| SEC-03 | DOC (kein App-Sandbox, bewusst; Hinweis im Tracker) | — |
| SEC-04 | FIX (Screenshot in `~/Library/Application Support/<BundleID>/`) | `xcode/Test/ViewController.swift` |
| SEC-05 | FIX (Restore via Bundle-ID + `NSWorkspace`, `Process()` entfällt) | `xcode/Test/ViewController.swift` |
| SEC-06 | DOC (siehe ISSUE-01, Build-Anleitung) | — |

Die alte, im Repo enthaltene `Later.dmg` bleibt unverändert — sie ist nicht neu zu bauen ohne Xcode und ohne Apple-Developer-ID-Signatur. Für den funktionstüchtigen Binary muss der Workflow unter „Build-Anleitung" einmalig durchlaufen werden.

## Bekannte offene Punkte / Nacharbeit

- `Main.storyboard` referenziert die Font-Familie „Inter-Regular" direkt; auf macOS wird der Registrierungs­pfad via `ATSApplicationFontsPath` beim ersten Laden verbraucht — falls eine Font‑Datei fehlen sollte (Bundle-Layout), gleicht das System still auf `SF Pro` zurück. Verifizieren nach dem ersten Clean-Build.
- `Run Script`-Phase (Legacy‑Helper von `LaunchAtLogin`) wurde entfernt. Falls in Zukunft auf das klassische (pre-macOS 13) `LaunchAtLogin`-Package zurückgegangen wird, muss die Phase wiederhergestellt werden.
- Die alten Session‑Daten im `UserDefaults` (`apps` = Executable-URL-Liste) werden beim ersten Save durch Bundle-IDs überschrieben; ältere Sessions lassen sich dank `legacyURL`-Fallback trotzdem wiederherstellen.

