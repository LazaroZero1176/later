# Later



https://user-images.githubusercontent.com/7581348/176900722-6ceb1fb7-b235-4a6a-991c-6273edc31b30.mp4


Save all your Mac apps for later with one click 🖱️

Later is a Mac menu bar app that clears and restores your workspace with ease. Switch off from work, tidy up your desktop before screen sharing, schedule apps for later, and more.

> **v2.0 fork note** — this repo is a maintenance fork of [alyssaxuu/later](https://github.com/alyssaxuu/later). The original binary (`v1.91`) will not run on macOS 13+ (Ventura/Sonoma/Sequoia/Tahoe) due to deprecated APIs (`CGDisplayCreateImage`, `SMLoginItemSetEnabled`), missing privacy strings, and force-unwrap crashes on the first screenshot. The full audit of 23 issues + 6 security findings, and the fixes that went into v2.0, is documented in [`ISSUES.md`](./ISSUES.md).

<a href="https://www.producthunt.com/posts/later-aa762753-cafe-475e-9acb-d534de9e6adf?utm_source=badge-featured&utm_medium=badge&utm_souce=badge-later&#0045;aa762753&#0045;cafe&#0045;475e&#0045;9acb&#0045;d534de9e6adf" target="_blank"><img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=332569&theme=light" alt="Later - Save&#0032;all&#0032;your&#0032;Mac&#0032;apps&#0032;for&#0032;later&#0032;with&#0032;one&#0032;click | Product Hunt" style="width: 250px; height: 54px;" width="250" height="54" /></a>

> You can support the original project through [GitHub Sponsors](https://github.com/sponsors/alyssaxuu)! ❤️

Originally made by [Alyssa X](https://github.com/alyssaxuu) — no longer maintained upstream. This fork continues to track macOS compatibility.

## Table of contents

- [Features](#features)
- [Installing Later](#installing-later)
- [Troubleshooting](#troubleshooting)
- [Source code](#source-code)

## Features

👻 Hide or close all your apps<br> ⚡️ Restore your session with just one click<br> 👀 View metadata and a preview of your saved sessions<br> 🗂 **Six independent session slots** — switch between saved workspaces (e.g. "coding", "meeting", "off") with a 2×3 grid in the popover, each slot keeps its own app list, preview, and session-setup preset<br> ♻️ **Reusable session presets** — restoring a slot no longer empties it, so you can hop back to the same layout any time (optionally terminating everything that isn't part of it)<br> 🖱 **Right-click quickbar on the menu bar icon** — jump straight to any of the six slots and restore it in one click, or save the current desktop into any slot through the *Save current session to…* submenu (panic-button for "boss is coming")<br> ⌨️ **Configurable global shortcuts** — rebind Save / Restore and assign a one-key jump to each of the six slots from the gear menu's *Configure shortcuts…* sheet<br> 🧊 **Liquid Glass on macOS 26 Tahoe** — the popover adopts the system glass material automatically when you're on Tahoe<br> ⏱ **Per-slot reopen timer** — pause any slot for a fixed duration (15 min / 30 min / 1 h / 5 h) or schedule it to a specific clock time, optionally with a weekday pattern (daily or e.g. Mon/Tue/Thu). All six slots can be armed in parallel; timers survive an app quit.<br> 🔋 Save battery by closing your apps instead of leaving them open<br> ⚙️ Gear menu: website, shortcuts, Dock / menu bar visibility, Quit — plus advanced options in the popover (ignore apps, terminate vs hide, etc.)

## Installing Later

Requires **macOS 13.0 (Ventura) or later**.

1. Download the latest [`Later-2.6.1.dmg`](./Later-2.6.1.dmg) from this repo.
2. Open the DMG and drag `Later.app` into your `Applications` folder.
3. Because the binary is ad-hoc signed (no Apple Developer ID), macOS Gatekeeper will block it on first launch. Remove the quarantine attribute in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Later.app
   ```
   Alternatively: open `/Applications`, right-click `Later.app` → `Open` → confirm the warning dialog.
4. Start `Later.app` from `/Applications`. You'll see both a **menu bar icon** (moon symbol, top right) and a **Dock icon**.
5. On first "Save windows for later" click, macOS will ask for **Screen Recording** permission (required for the session preview thumbnail). Grant it and click "Save" again.

## Troubleshooting

**Menu bar icon is not visible**

Recent macOS versions let you hide specific app icons from the menu bar. If Later's moon icon doesn't appear:

- Open **System Settings → Control Center → Menu Bar Only** and make sure `Later` is enabled.
- If you use a menu bar manager (Bartender, Barbee, Hidden Bar, iBar, etc.), Later may have been auto-moved to the hidden/overflow section — set it to `Always Show` in the manager's preferences.
- As a fallback, Later always has a **Dock icon**. Clicking the Dock icon opens the popover directly.

**"Later.app is damaged and cannot be opened"**

That's the Gatekeeper quarantine warning — see step 3 above (`xattr -dr com.apple.quarantine ...`).

**"Later" cannot save my session / screenshot fails**

Grant Screen Recording permission: `System Settings → Privacy & Security → Screen Recording → enable Later`. Restart the app afterwards.

**My system apps (Finder, System Settings) don't hide**

That's intentional. Later ships with "Ignore system apps" enabled by default — it skips `Finder`, `System Settings`, `Activity Monitor`, `App Store` etc. Uncheck the option in the popover if you want those to hide too.

## Source code

You can open Later in Xcode if you'd like to make changes or develop it further.

1. Clone this repo.
2. Open `xcode/Later.xcodeproj` in Xcode 15 or later.
3. Xcode will resolve the Swift Package Manager dependencies automatically (`KeyboardShortcuts` `2.4.0`, `HotKey` `0.2.0` (legacy, kept for project compatibility), `LaunchAtLogin-Modern` `1.1.0`).
4. Build & run. For a distributable `.app`, use `Product → Archive`.
5. For Gatekeeper-friendly distribution you need an Apple Developer ID to sign and notarize — see the [Build-Anleitung section in `ISSUES.md`](./ISSUES.md#build-anleitung-saubere-distribution-für-aktuelles-macos).

## Changelog

**v2.6.1** (2026-04-18, this fork)
- **Hotfix: app crashed on launch on macOS 26.** The per-slot reopen timer introduced in v2.6.0 persisted its "not armed" sentinel as `NSNull()` inside an `NSArray` stored under `UserDefaults[reopen.fireDates]`. `NSNull` is not a valid property-list value, and Tahoe's CFPrefs validator rejects it with an uncaught `NSException` (`_CFPrefsValidateValueForKey → mutateError`). Because the manager is touched the first time `ViewController.refreshUIForActiveSlot()` runs — which happens inside `viewDidLoad`, which we force-load from `applicationDidFinishLaunching` to migrate shortcuts — every cold launch of 2.6.0 aborted with SIGABRT before the popover could render.
- Persistence schema is now a plain `[Double]` of fixed length 6, where `0` means "no timer armed" and any other value is a `timeIntervalSince1970`. `saveFireDates` writes only `Double`s, so CFPrefs is happy; `loadFireDates` reads the new format first and still tolerates the v2.6.0 legacy array defensively (`Date`, `NSNull`, `NSNumber`), so anyone who managed to write valid entries before the crash decodes without data loss. The singleton initializer also `removeObject(forKey:)`s any non-`[Double]` payload before re-seeding, so one launch of 2.6.1 scrubs the broken state permanently.
- No behavior or UI change beyond the crash fix — the per-slot timer feature shipped in 2.6.0 is identical. See [`ISSUES.md`](./ISSUES.md) ISSUE-37.
- DMG renamed to `Later-2.6.1.dmg`.

**v2.6.0** (2026-04-18, this fork)
- **Per-slot reopen timer.** The "Reopen this session" checkbox (previously a single global toggle called "Reopen windows in") is now bound to the active session slot. Each of the six slots remembers its own timer mode (off / duration / clock time) and parameters, so slot 1 can auto-reopen in 30 minutes while slot 2 is scheduled for 17:30 tomorrow, and both countdowns run in parallel. Switching between slots no longer cancels the previously running timer.
- **Clock-time mode with optional weekday recurrence.** The time dropdown has a new **"At specific time…"** entry that opens a compact sheet with an `NSDatePicker` and seven weekday checkboxes (Mon–Sun) plus **Daily** and **Clear** quick buttons. Leaving every weekday unchecked yields a one-shot schedule (next occurrence of HH:MM); checking some or all of them makes the schedule **recurring** — e.g. "Mon, Tue, Thu at 09:00" — so you can prepare a preset once and have Later restore it automatically every matching morning. Recurring schedules are autonomous: after firing they immediately compute the next matching date and re-arm themselves without needing a fresh Save.
- **Survives app quits.** Every armed slot's absolute fire date is persisted under `UserDefaults[reopen.fireDates]` (six-entry array). At launch the app walks the list: past one-shot fire dates trigger an immediate restore of that slot, past recurring ones fire once and rearm for the next matching weekday, future fire dates resume as live countdowns. Recurring schedules whose fire date expired while Later was quit re-derive the next occurrence on the fly from the slot's stored HH:MM and weekday pattern, so "Mon–Fri at 09:00" keeps firing even across week-long shutdowns.
- **Visual feedback.** Each SlotButton in the 2×3 grid now shows a small badge in its top-right corner while its timer is armed — a `clock` glyph for one-shot timers and a `repeat` glyph for recurring clock schedules. The slot's tooltip shows the live countdown for durations (`Reopens in 00:14:23`), the next HH:MM for one-shot clock schedules (`Reopens at 13:30`), or the full pattern (`Repeats Mon, Tue, Thu · next 09:00`) for recurring ones. The popover's existing in-line timer label picks the same format for the currently active slot.
- **Decoupled from the Save button for recurring schedules.** Duration timers and one-shot clock timers still start on Save as before (since "duration" is meaningful only relative to a save time). Recurring clock schedules, on the other hand, arm the moment you confirm them in the sheet and re-arm every time the slot is saved or refilled — matching the "set once, forget forever" mental model. Emptying a slot via its X button cancels the running timer but **preserves** the schedule, so refilling that slot picks up where the schedule left off.
- **Storage model.** `SessionSlotStore.Slot` gained five new fields (`reopenMode`, `reopenDurationMinutes`, `reopenClockHour`, `reopenClockMinute`, `reopenWeekdays`) with Codable defaults, so upgrading from v2.5.0 decodes existing JSON blobs transparently (mode `.off`, 15 min / 09:00, no recurrence). The single global `UserDefaults[waitCheckbox]` key the previous build used is no longer read.
- DMG renamed to `Later-2.6.0.dmg`.

**v2.5.0** (2026-04-18, this fork)
- **Configurable global shortcuts.** The gear menu's old *Disable all shortcuts* toggle has been retired in favour of two entries: **Configure shortcuts…**, which opens a dedicated Shortcuts window, and **Enable global shortcuts**, a master on/off that now acts as the checkmark master switch instead of the only control. The settings window lets you rebind or clear each shortcut with the standard macOS recorder — click a field and press the combo (or use the X to clear).
- **Eight named shortcuts in total**: `Save active session` (default `⌘⇧L`), `Restore active session` (default `⌘⇧R`), and six **Restore Slot 1…6** shortcuts with no defaults. Assigning e.g. `⌃F1` to slot 1 means pressing `⌃F1` from anywhere sets slot 1 as the active slot and restores it immediately — no popover, no extra click, same semantics as the right-click quickbar. The slot names in the sheet reflect the actual session name so you know which slot you're rebinding.
- Recordings are persisted through the [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) package (pinned `2.4.0`, `upToNextMajorVersion(2.3.0)`) under standard `UserDefaults` keys (`KeyboardShortcuts_<name>`). Disabling global shortcuts from the gear menu keeps the recordings — it only suppresses the handlers — so re-enabling is lossless.
- Migration: the legacy `⌘⇧L` / `⌘⇧R` defaults are seeded on first launch of v2.5.0, so anyone upgrading from v2.4.x keeps the familiar key combos without doing anything. The `switchKey` default keeps its historical polarity (`true` = disabled), so the gear menu's master toggle reflects the previous choice across the update.
- Shortcuts sheet behaves like a classic macOS dialog: **Save** (Return) keeps every change you made, **Cancel** (Escape) — and the red titlebar close button — revert every edit to the state you had when you opened the window. The window is hidden on close rather than destroyed, so in accessory-mode launches (Dock icon off) the rest of the app keeps running.
- DMG renamed to `Later-2.5.0.dmg`.

**v2.4.3** (2026-04-18, this fork)
- **Save sessions from the right-click quickbar.** The status-item context menu gained a new **Save current session to…** submenu listing all six slots. Picking a slot sets it active and immediately runs the same Save flow the green "Save windows for later" button triggers — screenshot, record running apps, hide/close everything according to the popover's current exclude/close settings — so the classic "boss is coming, make the desktop presentable" move is now a two-click gesture without ever opening the popover. Existing slot contents are overwritten without a confirmation dialog (the submenu labels show `overwrite <sessionName>` for occupied slots and `empty` for fresh ones to make that explicit).
- Restore submenu (from v2.4.2) is unchanged; the new save entry sits between the slot list and **Open Later…**.
- DMG renamed to `Later-2.4.3.dmg`.

**v2.4.2** (2026-04-18, this fork)
- **Right-click quickbar on the menu bar icon.** Right-clicking (or Ctrl-clicking) the moon icon now opens a compact session menu listing all six slots. Clicking a slot sets it active *and* restores it in a single step — no popover, no extra click — so switching workspaces from a keyboard shortcut is now also a one-second mouse move. Empty slots are shown disabled (`Slot N — empty`), the currently active slot is checkmarked (`Slot N — <sessionName>` with a ✓). The menu also has an **Open Later…** entry that brings up the regular popover, plus **Quit**. Left-click behavior is unchanged. The "Only apps from this session (close others)" checkbox in the popover still controls whether restore closes apps that aren't part of the slot, just like when you trigger restore from the green button.
- Implementation note (see [`ISSUES.md`](./ISSUES.md) ISSUE-33): the status-item button is configured with `sendAction(on: [.leftMouseUp, .rightMouseUp])`, and `togglePopover(_:)` sniffs `NSApp.currentEvent` to dispatch between the popover (left) and the quick menu (right / Ctrl). The quickbar uses `SessionSlotStore.slot(at:)` for titles/enabled state, which means Touch Bar–free restores work even if you've never opened the popover in the current session (the view controller is forced to load before `restoreSessionGlobal()` is called).
- DMG renamed to `Later-2.4.2.dmg`.

**v2.4.1** (2026-04-18, this fork)
- Follow-up to v2.4: added a **"Use Liquid Glass (Tahoe)" toggle** in the gear menu. Defaults to on when running on macOS 26+, and the menu item is hidden entirely on older macOS. Turning it off restores the exact legacy dark popover look from v2.3 — useful if the glass material is too subtle for your monitor or clashes with your wallpaper. The toggle takes effect immediately, even with the popover open; the user-readable label color in the session-setup row flips too, so nothing becomes unreadable. Persisted in `UserDefaults` under `useLiquidGlass`.
- DMG renamed to `Later-2.4.1.dmg`.

**v2.4** (2026-04-18, this fork)
- **Liquid Glass on macOS 26 (Tahoe).** When running on Tahoe or later, the popover now adopts the system Liquid Glass material instead of the fixed dark panel from earlier versions. The session preview box and the options box render with transparent fills so the glass material shows through the whole popover. The session-setup row uses semantic label colors and picks up the adaptive light/dark glass automatically. Older macOS (13.0–15.x) keeps the legacy dark popover look — the change is fully runtime-gated via `#available(macOS 26.0, *)`, no change to the 13.0 deployment target.
- DMG renamed to `Later-2.4.dmg`.

**v2.3.1** (2026-04-18, this fork)
- Follow-up fix to v2.3: restoring a session after a previous restore had terminated one of its apps now re-launches that app instead of silently skipping it. `activate()` used to match the still-terminating `NSRunningApplication` entry and short-circuit to `unhide()` on a zombie process — it now ignores terminated entries so the launch branch runs. See [`ISSUES.md`](./ISSUES.md) ISSUE-29.
- DMG renamed to `Later-2.3.1.dmg`.

**v2.3** (2026-04-18, this fork)
- **Sessions are now reusable presets.** Restoring a slot (green button, `Cmd+Shift+R`, or the 15-minute timer-wake) no longer clears it — the slot keeps its app list, screenshot, and session-setup binding, so you can hop back to the same workspace any time. Use the X on the preview box to forget a slot explicitly.
- The existing "Close all apps when restoring" checkbox is now relabelled **"Only apps from this session (close others)"** and has become a smart diff: when enabled, Later terminates only running apps that are **not** part of the target slot (Terminal and system apps remain protected), while apps that *are* part of the session simply get unhidden instead of restarted — no more flicker. When disabled, restore stays additive as before.
- Added a safety guard: triggering restore on an empty slot now beeps and does nothing, instead of quietly terminating everything because the close-others step ran with no target.
- See [`ISSUES.md`](./ISSUES.md) ISSUE-27 / ISSUE-28 for the before/after reasoning.
- DMG renamed to `Later-2.3.dmg`.

**v2.2** (2026-04-18, this fork)
- **Six session slots** (1–6, 2×3 grid) inside the popover. Save / restore / cancel actions, the session preview box, and the timer now all target the currently active slot. Switching slots loads that slot's view immediately.
- Each slot stores its own screenshot on disk (`screenshot-slot-<n>.jpg`); the legacy single-session data is migrated into slot 1 on first launch.
- **Per-slot session setup:** every slot remembers its own exclude profile (`All`, `Work`, `Presentation`, `Coding`, `Entertainment`, or any custom-renamed setup). Configure slot 1 for *Work* and slot 2 for *Coding*, and Later automatically applies the correct preset whenever you switch slots. The chosen preset is persisted per slot in `UserDefaults`.
- Empty slot preview area is **reserved** with a placeholder ("No session saved in this slot.") so the popover no longer shifts when you save, delete, or switch sessions.
- New `SessionSlotStore` with JSON persistence in `UserDefaults` (one blob per slot). The shared exclude-setup profiles are unchanged, but each session slot now also stores which profile it uses.
- Popover layout is now fully **content-driven**: the options box, the session section, and the popover height resize themselves to fit the visible content — no empty gaps below the slots, no clipped Save button when a session is stored vs. empty.
- Custom `SlotButton` rendering (layer-drawn background, accent colour when active, light text) replaces the native `.rounded` bezel that used to render black on the dark options box.
- Session-setup UI and default profile names are now **English** (`All`, `Work`, `Presentation`, `Coding`, `Entertainment`; "Edit…", "Session settings", "Add app…", "Remove", "Done"). Existing installs that still used the German defaults are migrated to the English names on first launch; custom names are preserved.
- Code + security review of the v2.2 changes — see [`ISSUES.md`](./ISSUES.md) ISSUE-24 / 25 / 26 and the new "Sicherheits-Review v2.2" section. No new High/Crit findings; three low/medium regressions fixed (register-default locale, migration ordering in `viewDidLoad`, placeholder-toggle leaking into the timer row).
- DMG artefact renamed to `Later-2.2.dmg`; build script now takes the version from a `LATER_VERSION` variable so bumping it touches one line.

**v2.1** (2026-04-17, this fork)
- Optional **Dock icon** and **menu bar icon** (persisted in preferences). At least one must stay enabled; otherwise only global shortcuts can open the app (unless shortcuts are disabled in the gear menu).
- These toggles live under the **gear (⚙️)** in the popover, not in the main options area, so the popover layout and the primary **Save windows for later** / restore actions stay fully visible.
- If the menu bar item is hidden or stuck in the overflow strip, the popover can still anchor to a **fallback position** at the top-center of the screen (see `AppDelegate`).

**v2.0** (2026-04-17, this fork)
- macOS 13.0+ support, 22 bugs + 6 security findings fixed — see [`ISSUES.md`](./ISSUES.md).
- Screenshot now uses ScreenCaptureKit with a CGWindowList fallback, no more force-unwrap crash.
- Autostart via modern `SMAppService` (`LaunchAtLogin-Modern` 1.1.0 pinned).
- App launching via `NSWorkspace.openApplication(at:)` — no more `Process()` + LaunchServices-bypass.
- All force-unwraps (`!`) replaced by safe unwrapping.
- Fonts now load via `ATSApplicationFontsPath` (correct macOS key, was `UIAppFonts`).
- Dock icon + menu bar icon both visible as reachable entry points (accessory→regular flip).
- SwiftPM dependencies pinned to tags (no more `branch=main` supply-chain risk).
- Deployment target bumped to macOS 13.0, JIT entitlement removed, Screen Recording usage string added.

**v1.91** — original release by Alyssa X, not compatible with macOS 13+.
