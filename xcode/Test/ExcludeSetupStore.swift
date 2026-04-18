//
//  ExcludeSetupStore.swift
//  Later
//
//  Four named session setups with per-slot bundle-ID exclude lists,
//  plus mode: all apps, or one selected slot.
//

import Foundation

enum ExcludeSetupMode: Equatable {
    case all
    case slot(Int)

    private static let prefix = "slot:"

    var rawValue: String {
        switch self {
        case .all: return "all"
        case .slot(let i): return Self.prefix + "\(i)"
        }
    }

    init?(rawValue: String) {
        if rawValue == "all" {
            self = .all
            return
        }
        if rawValue.hasPrefix(Self.prefix),
           let n = Int(rawValue.dropFirst(Self.prefix.count)),
           n >= 0, n < ExcludeSetupStore.slotCount {
            self = .slot(n)
            return
        }
        return nil
    }
}

enum ExcludeSetupStore {

    static let slotCount = 4

    private static let keyDisplayNames = "excludeSetup.displayNames"
    private static let keyBundleLists = "excludeSetup.bundleLists"
    private static let keyMode = "excludeSetup.mode"

    static let defaultDisplayNames = ["Arbeit", "Präsentation", "Coding", "Unterhaltung"]

    private static let defaults = UserDefaults.standard

    static func excludedBundleIDs(for mode: ExcludeSetupMode) -> Set<String> {
        switch mode {
        case .all:
            return []
        case .slot(let i):
            let lists = loadBundleLists()
            guard i >= 0, i < lists.count else { return [] }
            return Set(lists[i])
        }
    }

    static func currentMode() -> ExcludeSetupMode {
        guard let raw = defaults.string(forKey: keyMode), let m = ExcludeSetupMode(rawValue: raw) else {
            return .all
        }
        return m
    }

    static func setCurrentMode(_ mode: ExcludeSetupMode) {
        defaults.set(mode.rawValue, forKey: keyMode)
    }

    static func loadDisplayNames() -> [String] {
        if let a = defaults.array(forKey: keyDisplayNames) as? [String], a.count == slotCount {
            return a
        }
        return defaultDisplayNames
    }

    static func saveDisplayNames(_ names: [String]) {
        let trimmed = (0..<slotCount).map { i in
            i < names.count ? names[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        let nonEmpty = trimmed.map { $0.isEmpty ? "Setup" : $0 }
        defaults.set(nonEmpty, forKey: keyDisplayNames)
    }

    static func loadBundleLists() -> [[String]] {
        guard let data = defaults.data(forKey: keyBundleLists),
              let decoded = try? JSONDecoder().decode([[String]].self, from: data),
              decoded.count == slotCount else {
            return Array(repeating: [], count: slotCount)
        }
        return decoded
    }

    static func saveBundleLists(_ lists: [[String]]) {
        let normalized: [[String]] = (0..<slotCount).map { i in
            guard i < lists.count else { return [] }
            let unique = Array(Set(lists[i].filter { !$0.isEmpty }))
            return unique.sorted()
        }
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: keyBundleLists)
        }
    }

    static func migrateIfNeeded() {
        if defaults.array(forKey: keyDisplayNames) == nil {
            defaults.set(defaultDisplayNames, forKey: keyDisplayNames)
        }
        if defaults.data(forKey: keyBundleLists) == nil {
            saveBundleLists(Array(repeating: [], count: slotCount))
        }
        if defaults.string(forKey: keyMode) == nil {
            setCurrentMode(.all)
        }
    }
}
