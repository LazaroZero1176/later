//
//  SessionSlotStore.swift
//  Later
//
//  Persists up to 6 independent saved sessions (slots). Migrates legacy single-session keys.
//

import Foundation

enum SessionSlotStore {

    static let slotCount = 6

    private static let migratedKey = "sessionSlots.migrated"
    private static let activeIndexKey = "sessionSlots.activeIndex"
    private static let slotsKey = "sessionSlots.payloadsJSON"

    /// Per-slot reopen policy. Mirrors `SessionSlotStore.ReopenMode` case names
    /// in its `rawValue` so existing JSON encodings keep working after future
    /// additions. Added in v2.6.0.
    enum ReopenMode: String, Codable { case off, duration, clockTime }

    /// v2.8.0 — optional clock-time trigger for **Save windows for later** on
    /// this slot (independent from reopen / restore).
    enum SaveScheduleMode: String, Codable { case off, clockTime }

    /// One saved session worth of data (mirrors former flat UserDefaults keys).
    ///
    /// v2.6.0 added per-slot reopen-timer fields (`reopenMode`,
    /// `reopenDurationMinutes`, `reopenClockHour`, `reopenClockMinute`,
    /// `reopenWeekdays`). They decode with sensible defaults from legacy JSON
    /// blobs via the custom `init(from:)` below, so pre-2.6.0 installs upgrade
    /// transparently (`.off` policy, 15 min / 09:00, no recurrence).
    struct Slot: Codable, Equatable {
        var hasSession: Bool
        var lastState: Bool
        var date: String
        var sessionName: String
        var sessionFullName: String
        var totalSessions: String
        var appsLegacy: [String]
        var appNames: [String]
        var appBundleIDs: [String]

        // v2.6.0 per-slot reopen-timer fields.
        var reopenMode: ReopenMode = .off
        var reopenDurationMinutes: Int = 15       // 15 / 30 / 60 / 300
        var reopenClockHour: Int = 9              // 0...23
        var reopenClockMinute: Int = 0            // 0...59
        /// Calendar weekday values (1=Sun, 2=Mon, ... 7=Sat). Empty = one-shot
        /// clock time. Stored as `[Int]` (Codable friendly); callers use a
        /// `Set<Int>` for membership checks.
        var reopenWeekdays: [Int] = []

        // v2.8.0 scheduled save (clock time + optional weekdays).
        var saveScheduleMode: SaveScheduleMode = .off
        var saveClockHour: Int = 9
        var saveClockMinute: Int = 0
        var saveWeekdays: [Int] = []

        static let empty = Slot(
            hasSession: false,
            lastState: false,
            date: "",
            sessionName: "",
            sessionFullName: "",
            totalSessions: "0",
            appsLegacy: [],
            appNames: [],
            appBundleIDs: []
        )

        init(
            hasSession: Bool,
            lastState: Bool,
            date: String,
            sessionName: String,
            sessionFullName: String,
            totalSessions: String,
            appsLegacy: [String],
            appNames: [String],
            appBundleIDs: [String],
            reopenMode: ReopenMode = .off,
            reopenDurationMinutes: Int = 15,
            reopenClockHour: Int = 9,
            reopenClockMinute: Int = 0,
            reopenWeekdays: [Int] = [],
            saveScheduleMode: SaveScheduleMode = .off,
            saveClockHour: Int = 9,
            saveClockMinute: Int = 0,
            saveWeekdays: [Int] = []
        ) {
            self.hasSession = hasSession
            self.lastState = lastState
            self.date = date
            self.sessionName = sessionName
            self.sessionFullName = sessionFullName
            self.totalSessions = totalSessions
            self.appsLegacy = appsLegacy
            self.appNames = appNames
            self.appBundleIDs = appBundleIDs
            self.reopenMode = reopenMode
            self.reopenDurationMinutes = reopenDurationMinutes
            self.reopenClockHour = reopenClockHour
            self.reopenClockMinute = reopenClockMinute
            self.reopenWeekdays = reopenWeekdays
            self.saveScheduleMode = saveScheduleMode
            self.saveClockHour = saveClockHour
            self.saveClockMinute = saveClockMinute
            self.saveWeekdays = saveWeekdays
        }

        // Custom Codable with defaults for the v2.6.0 fields so legacy blobs
        // decode cleanly.
        private enum CodingKeys: String, CodingKey {
            case hasSession, lastState, date, sessionName, sessionFullName
            case totalSessions, appsLegacy, appNames, appBundleIDs
            case reopenMode, reopenDurationMinutes
            case reopenClockHour, reopenClockMinute, reopenWeekdays
            case saveScheduleMode, saveClockHour, saveClockMinute, saveWeekdays
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.hasSession       = try c.decode(Bool.self,     forKey: .hasSession)
            self.lastState        = try c.decode(Bool.self,     forKey: .lastState)
            self.date             = try c.decode(String.self,   forKey: .date)
            self.sessionName      = try c.decode(String.self,   forKey: .sessionName)
            self.sessionFullName  = try c.decode(String.self,   forKey: .sessionFullName)
            self.totalSessions    = try c.decode(String.self,   forKey: .totalSessions)
            self.appsLegacy       = try c.decode([String].self, forKey: .appsLegacy)
            self.appNames         = try c.decode([String].self, forKey: .appNames)
            self.appBundleIDs     = try c.decode([String].self, forKey: .appBundleIDs)
            self.reopenMode            = try c.decodeIfPresent(ReopenMode.self, forKey: .reopenMode) ?? .off
            self.reopenDurationMinutes = try c.decodeIfPresent(Int.self,        forKey: .reopenDurationMinutes) ?? 15
            self.reopenClockHour       = try c.decodeIfPresent(Int.self,        forKey: .reopenClockHour) ?? 9
            self.reopenClockMinute     = try c.decodeIfPresent(Int.self,        forKey: .reopenClockMinute) ?? 0
            self.reopenWeekdays        = try c.decodeIfPresent([Int].self,      forKey: .reopenWeekdays) ?? []
            self.saveScheduleMode      = try c.decodeIfPresent(SaveScheduleMode.self, forKey: .saveScheduleMode) ?? .off
            self.saveClockHour         = try c.decodeIfPresent(Int.self,        forKey: .saveClockHour) ?? 9
            self.saveClockMinute       = try c.decodeIfPresent(Int.self,        forKey: .saveClockMinute) ?? 0
            self.saveWeekdays          = try c.decodeIfPresent([Int].self,      forKey: .saveWeekdays) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(hasSession,       forKey: .hasSession)
            try c.encode(lastState,        forKey: .lastState)
            try c.encode(date,             forKey: .date)
            try c.encode(sessionName,      forKey: .sessionName)
            try c.encode(sessionFullName,  forKey: .sessionFullName)
            try c.encode(totalSessions,    forKey: .totalSessions)
            try c.encode(appsLegacy,       forKey: .appsLegacy)
            try c.encode(appNames,         forKey: .appNames)
            try c.encode(appBundleIDs,     forKey: .appBundleIDs)
            try c.encode(reopenMode,            forKey: .reopenMode)
            try c.encode(reopenDurationMinutes, forKey: .reopenDurationMinutes)
            try c.encode(reopenClockHour,       forKey: .reopenClockHour)
            try c.encode(reopenClockMinute,     forKey: .reopenClockMinute)
            try c.encode(reopenWeekdays,        forKey: .reopenWeekdays)
            try c.encode(saveScheduleMode,     forKey: .saveScheduleMode)
            try c.encode(saveClockHour,        forKey: .saveClockHour)
            try c.encode(saveClockMinute,      forKey: .saveClockMinute)
            try c.encode(saveWeekdays,         forKey: .saveWeekdays)
        }

        /// Resolved policy for the current timer fields. Used by
        /// `ReopenTimerManager` and the UI.
        var activeReopenPolicy: ReopenPolicy {
            switch reopenMode {
            case .off:
                return .off
            case .duration:
                return .duration(minutes: reopenDurationMinutes)
            case .clockTime:
                return .clockTime(
                    hour: reopenClockHour,
                    minute: reopenClockMinute,
                    weekdays: Set(reopenWeekdays)
                )
            }
        }

        /// Clock-time policy for scheduled **Save** (v2.8.0). Independent from reopen.
        var activeSaveSchedulePolicy: ReopenPolicy {
            switch saveScheduleMode {
            case .off:
                return .off
            case .clockTime:
                return .clockTime(
                    hour: saveClockHour,
                    minute: saveClockMinute,
                    weekdays: Set(saveWeekdays)
                )
            }
        }
    }

    // MARK: - Migration

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }

        var slots = (0..<slotCount).map { _ in Slot.empty }

        if defaults.bool(forKey: "session") {
            slots[0] = Slot(
                hasSession: true,
                lastState: defaults.bool(forKey: "lastState"),
                date: defaults.string(forKey: "date") ?? "",
                sessionName: defaults.string(forKey: "sessionName") ?? "",
                sessionFullName: defaults.string(forKey: "sessionFullName") ?? "",
                totalSessions: defaults.string(forKey: "totalSessions") ?? "0",
                appsLegacy: defaults.array(forKey: "apps") as? [String] ?? [],
                appNames: defaults.array(forKey: "appNames") as? [String] ?? [],
                appBundleIDs: defaults.array(forKey: "appBundleIDs") as? [String] ?? []
            )
        }

        saveSlots(slots, defaults: defaults)
        if defaults.object(forKey: activeIndexKey) == nil {
            defaults.set(0, forKey: activeIndexKey)
        }

        if let dir = appSupportDirectory() {
            let legacy = dir.appendingPathComponent("screenshot.jpg", isDirectory: false)
            let first = dir.appendingPathComponent(screenshotFileName(for: 0), isDirectory: false)
            if FileManager.default.fileExists(atPath: legacy.path),
               !FileManager.default.fileExists(atPath: first.path) {
                try? FileManager.default.moveItem(at: legacy, to: first)
            }
        }

        defaults.set(true, forKey: migratedKey)
    }

    // MARK: - Active slot

    static func activeIndex(defaults: UserDefaults = .standard) -> Int {
        let i = defaults.integer(forKey: activeIndexKey)
        return min(max(i, 0), slotCount - 1)
    }

    static func setActiveIndex(_ index: Int, defaults: UserDefaults = .standard) {
        defaults.set(min(max(index, 0), slotCount - 1), forKey: activeIndexKey)
    }

    // MARK: - Read / write

    static func slot(at index: Int, defaults: UserDefaults = .standard) -> Slot {
        let slots = loadSlots(defaults: defaults)
        guard index >= 0 && index < slotCount else { return .empty }
        return slots[index]
    }

    static func setSlot(at index: Int, _ slot: Slot, defaults: UserDefaults = .standard) {
        var slots = loadSlots(defaults: defaults)
        guard index >= 0 && index < slotCount else { return }
        slots[index] = slot
        saveSlots(slots, defaults: defaults)
    }

    static func allSlots(defaults: UserDefaults = .standard) -> [Slot] {
        loadSlots(defaults: defaults)
    }

    // MARK: - Screenshot path per slot

    static func screenshotURL(for slotIndex: Int) -> URL? {
        appSupportDirectory()?.appendingPathComponent(screenshotFileName(for: slotIndex), isDirectory: false)
    }

    static func screenshotFileName(for slotIndex: Int) -> String {
        "screenshot-slot-\(slotIndex).jpg"
    }

    // MARK: - Private

    private static func loadSlots(defaults: UserDefaults) -> [Slot] {
        guard let data = defaults.data(forKey: slotsKey) else {
            return (0..<slotCount).map { _ in .empty }
        }
        if let decoded = try? JSONDecoder().decode([Slot].self, from: data), decoded.count == slotCount {
            return decoded
        }
        return (0..<slotCount).map { _ in .empty }
    }

    private static func saveSlots(_ slots: [Slot], defaults: UserDefaults) {
        guard slots.count == slotCount, let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: slotsKey)
    }

    private static func appSupportDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let bundleID = Bundle.main.bundleIdentifier ?? "Later"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("Later: SessionSlotStore cannot create app support dir: \(error)")
            return nil
        }
        return dir
    }
}
