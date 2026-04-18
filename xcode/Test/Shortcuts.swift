import KeyboardShortcuts

// MARK: - Named global shortcuts (v2.5.0)
//
// Centralized declaration of every global keyboard shortcut the app exposes.
// Each name is backed by `UserDefaults` under the key `KeyboardShortcuts_<name>`
// by the `KeyboardShortcuts` package — we never read/write those defaults
// directly, we only reference the names here.
//
// Default bindings match the legacy v2.4.x hardcoded hotkeys for
// continuity: ⌘⇧L saves the active session, ⌘⇧R restores it. The six
// per-slot restore shortcuts intentionally have no defaults; users opt in
// via the gear menu's "Configure shortcuts…" sheet.
extension KeyboardShortcuts.Name {
    static let saveActiveSession = Self(
        "saveActiveSession",
        default: .init(.l, modifiers: [.command, .shift])
    )
    static let restoreActiveSession = Self(
        "restoreActiveSession",
        default: .init(.r, modifiers: [.command, .shift])
    )

    static let restoreSlot1 = Self("restoreSlot1")
    static let restoreSlot2 = Self("restoreSlot2")
    static let restoreSlot3 = Self("restoreSlot3")
    static let restoreSlot4 = Self("restoreSlot4")
    static let restoreSlot5 = Self("restoreSlot5")
    static let restoreSlot6 = Self("restoreSlot6")

    /// Per-slot restore hotkeys ordered by slot index (0-based).
    static let allSlotRestore: [KeyboardShortcuts.Name] = [
        .restoreSlot1, .restoreSlot2, .restoreSlot3,
        .restoreSlot4, .restoreSlot5, .restoreSlot6
    ]

    /// Every name the app listens on — used by the master enable/disable
    /// toggle in the gear menu so enabling/disabling stays atomic.
    static let allAppShortcuts: [KeyboardShortcuts.Name] =
        [.saveActiveSession, .restoreActiveSession] + allSlotRestore
}
