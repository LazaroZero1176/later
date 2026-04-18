//
//  ScheduledSaveTimerManager.swift
//  Later
//
//  v2.8.0 — per-slot clock-time triggers for **Save windows for later**
//  (independent from `ReopenTimerManager`). Persists fire dates under
//  `saveSchedule.fireDates` ([Double]×6, 0 = not armed).
//

import Foundation

final class ScheduledSaveTimerManager {

    static let shared = ScheduledSaveTimerManager()

    private init() {
        if let raw = defaults.array(forKey: fireDatesKey) as? [Double],
           raw.count == SessionSlotStore.slotCount {
            return
        }
        defaults.removeObject(forKey: fireDatesKey)
        saveFireDates([Date?](repeating: nil, count: SessionSlotStore.slotCount))
    }

    /// Fires on the main queue with the slot index; AppDelegate runs
    /// `saveSessionGlobal()` for that slot.
    var onSaveFire: ((Int) -> Void)?

    func schedule(slotIndex: Int, policy: ReopenPolicy) {
        guard (0..<SessionSlotStore.slotCount).contains(slotIndex) else { return }
        cancel(slotIndex: slotIndex)
        switch policy {
        case .off, .duration:
            return
        case .clockTime(let h, let m, let weekdays):
            guard let fire = nextFireDate(after: Date(), hour: h, minute: m, weekdays: weekdays) else { return }
            armTimer(slotIndex: slotIndex, fireDate: fire, policy: policy)
        }
    }

    func cancel(slotIndex: Int) {
        guard (0..<SessionSlotStore.slotCount).contains(slotIndex) else { return }
        timers[slotIndex]?.invalidate()
        timers[slotIndex] = nil
        policies[slotIndex] = nil
        var dates = loadFireDates()
        dates[slotIndex] = nil
        saveFireDates(dates)
    }

    func fireDate(for slotIndex: Int) -> Date? {
        guard (0..<SessionSlotStore.slotCount).contains(slotIndex) else { return nil }
        return loadFireDates()[slotIndex]
    }

    func remainingString(for slotIndex: Int) -> String? {
        guard let fire = fireDate(for: slotIndex) else { return nil }
        let remaining = fire.timeIntervalSinceNow
        if remaining <= 0 { return "Saving now…" }
        let total = Int(remaining)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "Saving in %02d:%02d:%02d", h, m, s)
    }

    func restoreFromDisk() {
        let now = Date()
        let dates = loadFireDates()
        let slots = SessionSlotStore.allSlots()
        for i in 0..<SessionSlotStore.slotCount {
            let policy = slots[i].activeSaveSchedulePolicy
            let persisted = dates[i]

            switch policy {
            case .off, .duration:
                if persisted != nil {
                    var d = loadFireDates()
                    d[i] = nil
                    saveFireDates(d)
                }

            case .clockTime(let h, let m, let weekdays):
                policies[i] = policy
                if let fire = persisted {
                    if fire <= now {
                        fireSlot(i, policy: policy)
                    } else {
                        scheduleTimer(slotIndex: i, fireDate: fire, policy: policy)
                    }
                } else if let fire = nextFireDate(after: now, hour: h, minute: m, weekdays: weekdays) {
                    armTimer(slotIndex: i, fireDate: fire, policy: policy)
                }
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let fireDatesKey = "saveSchedule.fireDates"

    private var timers: [Int: Timer] = [:]
    private var policies: [Int: ReopenPolicy] = [:]

    private func armTimer(slotIndex: Int, fireDate: Date, policy: ReopenPolicy) {
        policies[slotIndex] = policy
        persistFireDate(fireDate, slotIndex: slotIndex)
        scheduleTimer(slotIndex: slotIndex, fireDate: fireDate, policy: policy)
    }

    private func scheduleTimer(slotIndex: Int, fireDate: Date, policy: ReopenPolicy) {
        let interval = max(0.1, fireDate.timeIntervalSinceNow)
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.fireSlot(slotIndex, policy: policy)
        }
        RunLoop.main.add(t, forMode: .common)
        timers[slotIndex]?.invalidate()
        timers[slotIndex] = t
    }

    private func fireSlot(_ slotIndex: Int, policy: ReopenPolicy) {
        timers[slotIndex]?.invalidate()
        timers[slotIndex] = nil
        var dates = loadFireDates()
        dates[slotIndex] = nil
        saveFireDates(dates)

        if Thread.isMainThread {
            onSaveFire?(slotIndex)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onSaveFire?(slotIndex) }
        }

        if case .clockTime(let h, let m, let weekdays) = policy, !weekdays.isEmpty,
           let next = nextFireDate(after: Date(), hour: h, minute: m, weekdays: weekdays) {
            armTimer(slotIndex: slotIndex, fireDate: next, policy: policy)
        } else {
            policies[slotIndex] = nil
        }
    }

    private func nextFireDate(after reference: Date, hour: Int, minute: Int, weekdays: Set<Int>) -> Date? {
        let cal = Calendar.current
        if weekdays.isEmpty {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            return cal.nextDate(after: reference, matching: comps, matchingPolicy: .nextTime)
        }
        var best: Date?
        for day in weekdays where (1...7).contains(day) {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            comps.weekday = day
            if let cand = cal.nextDate(after: reference, matching: comps, matchingPolicy: .nextTime) {
                if best == nil || cand < best! {
                    best = cand
                }
            }
        }
        return best
    }

    private func loadFireDates() -> [Date?] {
        if let raw = defaults.array(forKey: fireDatesKey) as? [Double],
           raw.count == SessionSlotStore.slotCount {
            return raw.map { ti in ti > 0 ? Date(timeIntervalSince1970: ti) : nil }
        }
        return [Date?](repeating: nil, count: SessionSlotStore.slotCount)
    }

    private func saveFireDates(_ dates: [Date?]) {
        let raw: [Double] = dates.map { $0?.timeIntervalSince1970 ?? 0 }
        defaults.set(raw, forKey: fireDatesKey)
    }

    private func persistFireDate(_ date: Date, slotIndex: Int) {
        var dates = loadFireDates()
        guard (0..<dates.count).contains(slotIndex) else { return }
        dates[slotIndex] = date
        saveFireDates(dates)
    }
}
