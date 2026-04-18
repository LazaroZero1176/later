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

    /// One saved session worth of data (mirrors former flat UserDefaults keys).
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
