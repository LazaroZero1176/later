//
//  SessionTimerEditing.swift
//  Later
//
//  Shared helpers for per-slot reopen timers — used by `ViewController` and
//  `SessionTimePlannerController` so policy changes stay consistent. Future
//  v2.7 multi-timer / save+restore actions can extend this layer without
//  duplicating UI glue.
//

import Foundation

extension Notification.Name {
    /// Posted when any slot's reopen timer fields or armed state change outside
    /// the immediate popover flow (e.g. Time planner window).
    static let laterSessionTimersChanged = Notification.Name("com.alyssaxuu.Later.sessionTimersChanged")
}

enum SessionTimerEditing {

    /// True when persisted slot matches `draft` on all reopen fields (live
    /// `ReopenTimerManager` countdowns only make sense in that case).
    static func reopenFieldsMatch(_ draft: SessionSlotStore.Slot, persisted: SessionSlotStore.Slot) -> Bool {
        draft.reopenMode == persisted.reopenMode
            && draft.reopenDurationMinutes == persisted.reopenDurationMinutes
            && draft.reopenClockHour == persisted.reopenClockHour
            && draft.reopenClockMinute == persisted.reopenClockMinute
            && Set(draft.reopenWeekdays) == Set(persisted.reopenWeekdays)
    }

    /// Human-readable weekday list — "Mon, Tue" or "Daily" when all seven.
    static func weekdayListString(_ weekdays: Set<Int>) -> String {
        if weekdays.count == 7 { return "Daily" }
        let order = [2, 3, 4, 5, 6, 7, 1]
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return order
            .filter { weekdays.contains($0) }
            .compactMap { (1...7).contains($0) ? names[$0] : nil }
            .joined(separator: ", ")
    }

    /// One-line status for the Time planner rows and tooltips.
    static func summary(forSlotIndex slotIndex: Int) -> String {
        let slot = SessionSlotStore.slot(at: slotIndex)
        let mgr = ReopenTimerManager.shared
        switch slot.reopenMode {
        case .off:
            return "Reopen: off"
        case .duration:
            let minutes = slot.reopenDurationMinutes
            let label: String
            switch minutes {
            case 15: label = "15 minutes after save"
            case 30: label = "30 minutes after save"
            case 60: label = "1 hour after save"
            case 300: label = "5 hours after save"
            default: label = "\(minutes) minutes after save"
            }
            if mgr.fireDate(for: slotIndex) != nil, let r = mgr.remainingString(for: slotIndex) {
                return "\(label) — \(r)"
            }
            return label
        case .clockTime:
            let hh = String(format: "%02d", max(0, min(23, slot.reopenClockHour)))
            let mm = String(format: "%02d", max(0, min(59, slot.reopenClockMinute)))
            let weekdays = Set(slot.reopenWeekdays)
            if let fire = mgr.fireDate(for: slotIndex) {
                let df = DateFormatter()
                df.timeStyle = .short
                df.dateStyle = .none
                let when = df.string(from: fire)
                if weekdays.isEmpty {
                    return "Clock \(hh):\(mm) — next \(when)"
                }
                return "Clock \(weekdayListString(weekdays)) · \(hh):\(mm) — next \(when)"
            }
            if weekdays.isEmpty {
                return "Clock \(hh):\(mm) (arms when you save a session)"
            }
            return "Clock \(weekdayListString(weekdays)) · \(hh):\(mm) (arms when you save a session)"
        }
    }

    /// Status line for the Time planner while editing **draft** slots (may
    /// differ from disk until the user clicks Save).
    static func summaryForPlannerDraft(slot: SessionSlotStore.Slot, slotIndex: Int) -> String {
        let persisted = SessionSlotStore.slot(at: slotIndex)
        let reopenSynced = reopenFieldsMatch(slot, persisted: persisted)
        let mgr = ReopenTimerManager.shared

        switch slot.reopenMode {
        case .off:
            return "Reopen: off"
        case .duration:
            let minutes = slot.reopenDurationMinutes
            let label: String
            switch minutes {
            case 15: label = "15 minutes after save"
            case 30: label = "30 minutes after save"
            case 60: label = "1 hour after save"
            case 300: label = "5 hours after save"
            default: label = "\(minutes) minutes after save"
            }
            if reopenSynced, mgr.fireDate(for: slotIndex) != nil, let r = mgr.remainingString(for: slotIndex) {
                return "\(label) — \(r)"
            }
            if !reopenSynced {
                return "\(label) — click Save to apply"
            }
            return label
        case .clockTime:
            let hh = String(format: "%02d", max(0, min(23, slot.reopenClockHour)))
            let mm = String(format: "%02d", max(0, min(59, slot.reopenClockMinute)))
            let weekdays = Set(slot.reopenWeekdays)
            if reopenSynced, let fire = mgr.fireDate(for: slotIndex) {
                let df = DateFormatter()
                df.timeStyle = .short
                df.dateStyle = .none
                let when = df.string(from: fire)
                if weekdays.isEmpty {
                    return "Clock \(hh):\(mm) — next \(when)"
                }
                return "Clock \(weekdayListString(weekdays)) · \(hh):\(mm) — next \(when)"
            }
            if weekdays.isEmpty {
                if reopenSynced {
                    return "Clock \(hh):\(mm) (arms when you save a session)"
                }
                return "Clock \(hh):\(mm) — click Save to apply"
            }
            if reopenSynced {
                return "Clock \(weekdayListString(weekdays)) · \(hh):\(mm) (arms when you save a session)"
            }
            return "Clock \(weekdayListString(weekdays)) · \(hh):\(mm) — click Save to apply"
        }
    }

    /// Persists all six draft slots and reconciles `ReopenTimerManager` (same
    /// semantics as applying each change immediately in the popover).
    static func commitPlannerDraft(_ slots: [SessionSlotStore.Slot]) {
        guard slots.count == SessionSlotStore.slotCount else { return }
        for i in 0..<SessionSlotStore.slotCount {
            SessionSlotStore.setSlot(at: i, slots[i])
        }
        for i in 0..<SessionSlotStore.slotCount {
            let slot = slots[i]
            switch slot.reopenMode {
            case .off:
                ReopenTimerManager.shared.cancel(slotIndex: i)
            case .duration:
                ReopenTimerManager.shared.cancel(slotIndex: i)
            case .clockTime:
                if slot.hasSession {
                    ReopenTimerManager.shared.schedule(slotIndex: i, policy: slot.activeReopenPolicy)
                } else {
                    ReopenTimerManager.shared.cancel(slotIndex: i)
                }
            }
        }
        postTimersChangedNotification()
    }

    static func postTimersChangedNotification() {
        NotificationCenter.default.post(name: .laterSessionTimersChanged, object: nil)
    }

    static func applyOff(slotIndex: Int) {
        var slot = SessionSlotStore.slot(at: slotIndex)
        slot.reopenMode = .off
        SessionSlotStore.setSlot(at: slotIndex, slot)
        ReopenTimerManager.shared.cancel(slotIndex: slotIndex)
        postTimersChangedNotification()
    }

    static func applyDuration(slotIndex: Int, minutes: Int) {
        var slot = SessionSlotStore.slot(at: slotIndex)
        slot.reopenMode = .duration
        slot.reopenDurationMinutes = minutes
        SessionSlotStore.setSlot(at: slotIndex, slot)
        ReopenTimerManager.shared.cancel(slotIndex: slotIndex)
        postTimersChangedNotification()
    }

    static func applyClockTime(slotIndex: Int, hour: Int, minute: Int, weekdays: Set<Int>) {
        var slot = SessionSlotStore.slot(at: slotIndex)
        slot.reopenMode = .clockTime
        slot.reopenClockHour = max(0, min(23, hour))
        slot.reopenClockMinute = max(0, min(59, minute))
        slot.reopenWeekdays = weekdays.sorted()
        SessionSlotStore.setSlot(at: slotIndex, slot)
        if slot.hasSession {
            ReopenTimerManager.shared.schedule(slotIndex: slotIndex, policy: slot.activeReopenPolicy)
        } else {
            ReopenTimerManager.shared.cancel(slotIndex: slotIndex)
        }
        postTimersChangedNotification()
    }
}
