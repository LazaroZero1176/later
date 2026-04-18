//
//  ReopenTimerManager.swift
//  Later
//
//  Single source of truth for the six per-slot reopen timers (v2.6.0).
//
//  Each slot can be armed with a duration (N minutes from now) or a clock
//  time (next HH:MM, optionally restricted to a weekday pattern). Clock-time
//  timers with weekdays are *recurring*: after each fire the manager computes
//  the next matching date and re-arms itself. Duration timers and one-shot
//  clock-time timers clear after firing.
//
//  State survives app quits: every armed slot's absolute fire date is
//  persisted to UserDefaults (`reopen.fireDates`, fixed-length 6 array). On
//  launch AppDelegate calls `restoreFromDisk()`, which fires any past one-shots
//  once, rearms past recurring schedules for the next matching date, and
//  resumes future fire dates as live Timers.
//

import Foundation

/// Declarative reopen policy for a session slot. Persisted indirectly via
/// `SessionSlotStore.Slot`; the manager only deals with the policy at
/// schedule time.
enum ReopenPolicy: Equatable {
    case off
    case duration(minutes: Int)
    /// `weekdays` uses `Calendar.weekday` values (1=Sun ... 7=Sat). Empty
    /// set = one-shot (next occurrence of HH:MM). Non-empty = recurring.
    case clockTime(hour: Int, minute: Int, weekdays: Set<Int>)
}

final class ReopenTimerManager {

    static let shared = ReopenTimerManager()

    private init() {
        // Seed the persisted-fireDates array to fixed length so index writes
        // below are always safe. 0 entries mean "no timer armed".
        //
        // v2.6.0 shipped a broken seed that stored NSNull() as the "no timer"
        // sentinel. NSNull is not a valid plist value; on macOS 26 CFPrefs
        // rejects it with an uncaught NSException the moment the singleton
        // is first touched (see ISSUE-37). We now persist a [Double] of
        // fixed length, with 0 meaning "not armed", which is plist-safe.
        //
        // If the on-disk value is anything other than a valid [Double] of
        // slotCount length (e.g. a legacy array containing NSNull from a
        // crashed v2.6.0 install), we drop it before re-seeding — otherwise
        // `defaults.set` against a container with NSNull keeps triggering
        // the validator.
        if let raw = defaults.array(forKey: fireDatesKey) as? [Double],
           raw.count == SessionSlotStore.slotCount {
            return
        }
        defaults.removeObject(forKey: fireDatesKey)
        saveFireDates([Date?](repeating: nil, count: SessionSlotStore.slotCount))
    }

    // MARK: - Public surface

    /// AppDelegate wires this once at launch. `slotIndex` is the slot that
    /// just fired and should be restored. Called on the main queue.
    var onFire: ((Int) -> Void)?

    /// (Re)schedule a slot. Cancels any existing timer for that slot first
    /// and overwrites its persisted fire date.
    func schedule(slotIndex: Int, policy: ReopenPolicy) {
        guard (0..<SessionSlotStore.slotCount).contains(slotIndex) else { return }
        cancel(slotIndex: slotIndex)

        switch policy {
        case .off:
            // cancel() already cleared state; nothing to arm.
            return
        case .duration(let minutes):
            let mins = max(1, minutes)
            let fire = Date().addingTimeInterval(Double(mins) * 60)
            armTimer(slotIndex: slotIndex, fireDate: fire, policy: policy)
        case .clockTime(let h, let m, let weekdays):
            guard let fire = nextFireDate(after: Date(), hour: h, minute: m, weekdays: weekdays) else { return }
            armTimer(slotIndex: slotIndex, fireDate: fire, policy: policy)
        }
    }

    /// Cancel an armed slot. Safe to call against an un-armed slot. Does not
    /// touch the slot's stored `reopenMode` — the next refill / save can
    /// re-arm using the same policy.
    func cancel(slotIndex: Int) {
        guard (0..<SessionSlotStore.slotCount).contains(slotIndex) else { return }
        timers[slotIndex]?.invalidate()
        timers[slotIndex] = nil
        policies[slotIndex] = nil
        var dates = loadFireDates()
        dates[slotIndex] = nil
        saveFireDates(dates)
    }

    /// Absolute wall-clock fire date for the slot, or nil when not armed.
    /// Drives the UI countdown label and tooltips.
    func fireDate(for slotIndex: Int) -> Date? {
        guard (0..<SessionSlotStore.slotCount).contains(slotIndex) else { return nil }
        return loadFireDates()[slotIndex]
    }

    /// True when the slot is armed with a recurring clock-time schedule.
    /// Used by the UI to pick the "repeat" vs "clock" glyph.
    func isRecurring(slotIndex: Int) -> Bool {
        guard (0..<SessionSlotStore.slotCount).contains(slotIndex) else { return false }
        if case .clockTime(_, _, let weekdays) = policies[slotIndex] ?? .off {
            return !weekdays.isEmpty
        }
        return false
    }

    /// A short human-readable countdown / target string, or nil when not armed.
    func remainingString(for slotIndex: Int) -> String? {
        guard let fire = fireDate(for: slotIndex) else { return nil }
        let remaining = fire.timeIntervalSinceNow
        if remaining <= 0 { return "Reopening now…" }
        let total = Int(remaining)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "Reopening in %02d:%02d:%02d", h, m, s)
    }

    /// Called once from `AppDelegate.applicationDidFinishLaunching` to rewire
    /// in-memory timers from the persisted fire dates and the slots' stored
    /// reopen policies. Must run after `SessionSlotStore.migrateIfNeeded()`.
    func restoreFromDisk() {
        let now = Date()
        let dates = loadFireDates()
        let slots = SessionSlotStore.allSlots()
        for i in 0..<SessionSlotStore.slotCount {
            let policy = slots[i].activeReopenPolicy
            let persisted = dates[i]

            switch policy {
            case .off:
                // User turned the timer off since the last launch. Any
                // leftover persisted date is stale — drop it.
                if persisted != nil {
                    var d = loadFireDates()
                    d[i] = nil
                    saveFireDates(d)
                }

            case .duration:
                // Duration timers are one-shot and tied to a specific save
                // event; without a persisted fire date there's nothing to
                // resume. With one, fire now if past or resume if future.
                if let fire = persisted {
                    policies[i] = policy
                    if fire <= now {
                        fireSlot(i, policy: policy)
                    } else {
                        scheduleTimer(slotIndex: i, fireDate: fire, policy: policy)
                    }
                }

            case .clockTime(let h, let m, let weekdays):
                policies[i] = policy
                if let fire = persisted {
                    if fire <= now {
                        // Missed the window while the app was quit. Fire
                        // once; recurring schedules rearm automatically in
                        // fireSlot() below.
                        fireSlot(i, policy: policy)
                    } else {
                        scheduleTimer(slotIndex: i, fireDate: fire, policy: policy)
                    }
                } else if !weekdays.isEmpty, slots[i].hasSession {
                    // Autonomous recurring schedule without a persisted
                    // fireDate — compute the next occurrence and arm.
                    if let fire = nextFireDate(after: now, hour: h, minute: m, weekdays: weekdays) {
                        armTimer(slotIndex: i, fireDate: fire, policy: policy)
                    }
                }
            }
        }
    }

    // MARK: - Private

    private let defaults = UserDefaults.standard
    private let fireDatesKey = "reopen.fireDates"

    /// Live timers keyed by slot index (in-memory only).
    private var timers: [Int: Timer] = [:]

    /// Policy associated with the armed timer for that slot. Kept in memory
    /// so `fireSlot` can decide whether to rearm without re-reading the
    /// slot (which might change between schedule and fire).
    private var policies: [Int: ReopenPolicy] = [:]

    private func armTimer(slotIndex: Int, fireDate: Date, policy: ReopenPolicy) {
        policies[slotIndex] = policy
        persistFireDate(fireDate, slotIndex: slotIndex)
        scheduleTimer(slotIndex: slotIndex, fireDate: fireDate, policy: policy)
    }

    private func scheduleTimer(slotIndex: Int, fireDate: Date, policy: ReopenPolicy) {
        // Foundation caps Timer intervals to ~1e10 seconds; the policies here
        // top out around a week, well inside the safe range.
        let interval = max(0.1, fireDate.timeIntervalSinceNow)
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.fireSlot(slotIndex, policy: policy)
        }
        // Stay active while sheets / menus are tracking on the main runloop.
        RunLoop.main.add(t, forMode: .common)
        timers[slotIndex]?.invalidate()
        timers[slotIndex] = t
    }

    private func fireSlot(_ slotIndex: Int, policy: ReopenPolicy) {
        // Tear the current arming down before invoking the restore handler
        // so observers of `fireDate(for:)` see a consistent state.
        timers[slotIndex]?.invalidate()
        timers[slotIndex] = nil
        var dates = loadFireDates()
        dates[slotIndex] = nil
        saveFireDates(dates)

        if Thread.isMainThread {
            onFire?(slotIndex)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onFire?(slotIndex) }
        }

        // Recurring clock-time schedules rearm themselves immediately.
        if case .clockTime(let h, let m, let weekdays) = policy, !weekdays.isEmpty,
           let next = nextFireDate(after: Date(), hour: h, minute: m, weekdays: weekdays) {
            armTimer(slotIndex: slotIndex, fireDate: next, policy: policy)
        } else {
            policies[slotIndex] = nil
        }
    }

    // MARK: - Clock-time math

    /// Next wall-clock `Date` matching `HH:MM` on one of `weekdays` (empty
    /// set = any weekday). Returns nil only if Calendar fails, which would
    /// require a very broken locale setup.
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

    // MARK: - Persistence

    private func loadFireDates() -> [Date?] {
        // Preferred format (v2.6.1+): [Double] of `slotCount` TimeIntervals
        // since the 1970 epoch, with 0 meaning "no timer armed". We read
        // that fast path first because it is the only format we write.
        if let raw = defaults.array(forKey: fireDatesKey) as? [Double],
           raw.count == SessionSlotStore.slotCount {
            return raw.map { ti in ti > 0 ? Date(timeIntervalSince1970: ti) : nil }
        }
        // Legacy tolerance (v2.6.0): the broken seed wrote [Any] mixing
        // Date / NSNull / TimeInterval. On disk this should already have
        // been scrubbed by init()'s removeObject, but if somebody migrated
        // their UserDefaults plist by hand we still decode it gracefully.
        if let raw = defaults.array(forKey: fireDatesKey),
           raw.count == SessionSlotStore.slotCount {
            return raw.map { entry -> Date? in
                if let d = entry as? Date { return d }
                if entry is NSNull { return nil }
                if let ti = entry as? TimeInterval, ti > 0 {
                    return Date(timeIntervalSince1970: ti)
                }
                if let n = entry as? NSNumber {
                    let ti = n.doubleValue
                    return ti > 0 ? Date(timeIntervalSince1970: ti) : nil
                }
                return nil
            }
        }
        return [Date?](repeating: nil, count: SessionSlotStore.slotCount)
    }

    private func saveFireDates(_ dates: [Date?]) {
        // Write a plist-safe [Double]. 0 = no timer armed for that slot.
        // Rationale for NSNull removal: macOS 26's CFPrefs validator
        // rejects NSNull() with an uncaught NSException, which crashed
        // v2.6.0 on first launch — see ISSUE-37.
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
