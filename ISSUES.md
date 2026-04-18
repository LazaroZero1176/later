# Later — Issue Tracker

> Audit ausgeführt am 2026-04-17 auf macOS 26.5 (Tahoe, Build 25F5053d).
> v2.2-Audit ausgeführt am 2026-04-18 auf demselben System, Fokus: neue Slot- und Setup-Stores.
> Basisversion: `alyssaxuu/later` @ `master` — Original-Binary: `Later.dmg` v1.91 (BuildMachineOSBuild 21F79, SDK macosx12.3).
> Aktueller Build (dieses Repo): **v2.4.1 (Build 10)**, ad-hoc signiert, macOS 13.0+ deployment target, Xcode 26.4.1 / macOS 26.4 SDK.
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
| SEC-01 | Branch-Pinning von SwiftPM-Deps (`LaunchAtLogin`, `HotKey`) → Supply-Chain-Angriffsfläche. Jeder Fremd-Commit auf `main`/`master` wird beim nächsten `xcodebuild` gezogen. | HIGH |
| SEC-02 | `com.apple.security.cs.allow-jit` ohne Bedarf (kein eigener Interpreter / JIT). Öffnet R+W+X-Speicher. | MED |
| SEC-03 | Keine Sandbox (`com.apple.security.app-sandbox`) — App hat Vollzugriff auf Documents, Running-Apps, Prozess­start via `Process()`. Bei App-Store-Distribution nicht abnahmefähig. | MED (für Self-Distribution akzeptabel) |
| SEC-04 | Screenshot wird als `screenshot.jpg` in `~/Documents/` abgelegt — potenziell sensitive Daten in geteiltem Ordner; andere Apps können mitlesen. | MED |
| SEC-05 | `defaults.set(array, forKey: "apps")` speichert Executable-URLs ungeprüft (String). Bei Manipulation der plist könnte ein Angreifer beim nächsten „Restore" per `Process().run()` beliebige Binaries ausführen. | HIGH |
| SEC-06 | Keine Notarisierung / ad-hoc Signatur (ISSUE-01). | HIGH |

**Fixes (Sicherheit):**
- SEC-01 → siehe ISSUE-03/04 (Tag-Pinning).
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
| SEC-01 | FIX (Tag-Pinning beider Deps) | siehe ISSUE-03/04 |
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

