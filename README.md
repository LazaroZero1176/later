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

👻 Hide or close all your apps<br> ⚡️ Restore your session with just one click<br> 👀 View metadata and a preview of your saved sessions<br> 🗂 **Six independent session slots** — switch between saved workspaces (e.g. "coding", "meeting", "off") with a 2×3 grid in the popover, each slot keeps its own app list, preview, and session-setup preset<br> ⏱ Schedule apps to reopen after some time to get back in the flow<br> 🔋 Save battery by closing your apps instead of leaving them open<br> ⌨️ Keyboard shortcuts to save and restore your session<br> ⚙️ Gear menu: website, shortcuts, Dock / menu bar visibility, Quit — plus advanced options in the popover (ignore apps, terminate vs hide, etc.)

## Installing Later

Requires **macOS 13.0 (Ventura) or later**.

1. Download the latest [`Later-2.2.dmg`](./Later-2.2.dmg) from this repo.
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
3. Xcode will resolve the Swift Package Manager dependencies automatically (`HotKey` `0.2.0`, `LaunchAtLogin-Modern` `1.1.0`).
4. Build & run. For a distributable `.app`, use `Product → Archive`.
5. For Gatekeeper-friendly distribution you need an Apple Developer ID to sign and notarize — see the [Build-Anleitung section in `ISSUES.md`](./ISSUES.md#build-anleitung-saubere-distribution-für-aktuelles-macos).

## Changelog

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
