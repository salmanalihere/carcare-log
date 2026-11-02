import Foundation
import UserNotifications

/// Local notifications. Permission is requested ONLY when the user turns
/// reminders on in Settings or creates a schedule with notifications —
/// never at app launch.
enum NotificationService {
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch { return false }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // Namespaced identifiers (FIX 18) — stable per record, so re-saving a
    // record REPLACES its pending request instead of duplicating it.
    static func maintenanceIdentifier(_ id: UUID) -> String { "cc-maintenance-\(id.uuidString)" }
    static func insuranceIdentifier(_ vehicleID: UUID) -> String { "cc-insurance-\(vehicleID.uuidString)" }
    static func registrationIdentifier(_ vehicleID: UUID) -> String { "cc-registration-\(vehicleID.uuidString)" }
    static func documentIdentifier(_ id: UUID) -> String { "cc-document-\(id.uuidString)" }
    static func reminderIdentifier(_ id: UUID) -> String { "cc-reminder-\(id.uuidString)" }

    /// Schedules a date-based reminder `leadDays` before `dueDate` (and on the day if leadDays == 0).
    static func schedule(id: UUID, title: String, body: String, dueDate: Date, leadDays: Int) {
        schedule(identifier: maintenanceIdentifier(id), title: title, body: body, dueDate: dueDate, leadDays: leadDays)
    }

    static func schedule(identifier: String, title: String, body: String, dueDate: Date, leadDays: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let fireDate = Calendar.current.date(byAdding: .day, value: -max(0, leadDays), to: dueDate) ?? dueDate
        guard fireDate > Date.now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel(id: UUID) { cancel(identifier: maintenanceIdentifier(id)) }
    static func cancelDocument(id: UUID) { cancel(identifier: documentIdentifier(id)) }
    static func cancelReminder(id: UUID) { cancel(identifier: reminderIdentifier(id)) }
    static func cancelInsurance(vehicleID: UUID) { cancel(identifier: insuranceIdentifier(vehicleID)) }
    static func cancelRegistration(vehicleID: UUID) { cancel(identifier: registrationIdentifier(vehicleID)) }

    static func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Re-arms (or cancels) every date-based item for a vehicle, honouring the
    /// GLOBAL reminders switch and each category switch. When a category is
    /// off, its pending requests are actively cancelled — not just skipped.
    static func reschedule(vehicle: Vehicle, globalEnabled: Bool, maintenanceEnabled: Bool, insuranceEnabled: Bool, registrationEnabled: Bool) {
        guard globalEnabled else {
            for s in vehicle.schedules { cancel(id: s.id) }
            cancelInsurance(vehicleID: vehicle.id)
            cancelRegistration(vehicleID: vehicle.id)
            for d in vehicle.documents { cancelDocument(id: d.id) }
            for r in vehicle.reminders { cancelReminder(id: r.id) }
            return
        }
        for s in vehicle.schedules {
            if !s.isCompleted && s.notificationsEnabled && maintenanceEnabled, let d = s.dueDate {
                schedule(id: s.id, title: "Maintenance due soon",
                         body: "\(s.title) for \(vehicle.displayName) is coming up.",
                         dueDate: d, leadDays: s.reminderLeadDays)
            } else {
                cancel(id: s.id)
            }
        }
        if insuranceEnabled, let d = vehicle.insuranceExpiry {
            schedule(identifier: insuranceIdentifier(vehicle.id), title: "Insurance expiring",
                     body: "Insurance for \(vehicle.displayName) expires soon.",
                     dueDate: d, leadDays: 30)
        } else {
            cancelInsurance(vehicleID: vehicle.id)
        }
        if registrationEnabled, let d = vehicle.registrationExpiry {
            schedule(identifier: registrationIdentifier(vehicle.id), title: "Registration expiring",
                     body: "Registration for \(vehicle.displayName) expires soon.",
                     dueDate: d, leadDays: 30)
        } else {
            cancelRegistration(vehicleID: vehicle.id)
        }
        for doc in vehicle.documents {
            let categoryOn: Bool
            switch doc.type {
            case .insurance: categoryOn = insuranceEnabled
            case .registration: categoryOn = registrationEnabled
            default: categoryOn = true
            }
            if categoryOn, let d = doc.expiryDate {
                schedule(identifier: documentIdentifier(doc.id), title: "Document expiring",
                         body: "\(doc.name) for \(vehicle.displayName) expires soon.",
                         dueDate: d, leadDays: 30)
            } else {
                cancelDocument(id: doc.id)
            }
        }
        for r in vehicle.reminders {
            if r.isEnabled, let d = r.date {
                schedule(identifier: reminderIdentifier(r.id), title: r.title, body: "Reminder for \(vehicle.displayName).",
                         dueDate: d, leadDays: r.leadDays)
            } else {
                cancelReminder(id: r.id)
            }
        }
    }

    static func rescheduleAll(vehicles: [Vehicle], globalEnabled: Bool, maintenanceEnabled: Bool, insuranceEnabled: Bool, registrationEnabled: Bool) {
        if !globalEnabled { cancelAll(); return }
        for v in vehicles {
            reschedule(vehicle: v, globalEnabled: true, maintenanceEnabled: maintenanceEnabled,
                       insuranceEnabled: insuranceEnabled, registrationEnabled: registrationEnabled)
        }
    }
}
