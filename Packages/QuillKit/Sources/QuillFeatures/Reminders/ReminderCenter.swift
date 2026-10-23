import Foundation
import UserNotifications

/// Erinnerung an ein To-do (15.4, ADR-033): steht nur als geplante Mitteilung im System.
public struct Reminder: Equatable, Sendable {
    public let blockID: UUID
    public let pageID: UUID
    public let date: Date
    /// Text des To-dos und Titel der Seite (leer bei „Ohne Titel“), wie in der Mitteilung.
    public let text: String
    public let pageTitle: String
}

/// Wohin Quill Erinnerungen plant: Mitteilungen des Macs oder ein Ersatz für Test-Stores.
protocol ReminderCenter: Sendable {
    /// Fragt beim ersten Mal nach der Erlaubnis; `false`, wenn Mitteilungen aus sind.
    func authorize() async throws -> Bool
    /// Noch nicht fällige Erinnerungen.
    func pending() async -> [Reminder]
    /// Legt an oder ersetzt die Erinnerung des Blocks.
    func schedule(_ reminder: Reminder) async throws
    func cancel(_ blockIDs: [UUID]) async
}

/// Mitteilungen des Macs, nur für den echten Store.
struct SystemReminderCenter: ReminderCenter {
    private static let prefix = "reminder-"

    func authorize() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func pending() async -> [Reminder] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix(Self.prefix) else { return nil }
            return Self.reminder(request.content.userInfo)
        }
    }

    func schedule(_ reminder: Reminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.text
        content.body = PageLabel.title(reminder.pageTitle)
        content.sound = .default
        content.userInfo = [
            "blockID": reminder.blockID.uuidString, "pageID": reminder.pageID.uuidString,
            "date": reminder.date.timeIntervalSince1970, "text": reminder.text, "pageTitle": reminder.pageTitle,
        ]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
        let request = UNNotificationRequest(
            identifier: Self.prefix + reminder.blockID.uuidString, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    func cancel(_ blockIDs: [UUID]) async {
        guard !blockIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: blockIDs.map { Self.prefix + $0.uuidString })
    }

    /// Seite aus einer Mitteilung, für den Klick darauf.
    static func pageID(_ userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo["pageID"] as? String).flatMap(UUID.init(uuidString:))
    }

    private static func reminder(_ userInfo: [AnyHashable: Any]) -> Reminder? {
        guard let block = (userInfo["blockID"] as? String).flatMap(UUID.init(uuidString:)), let page = pageID(userInfo),
              let date = userInfo["date"] as? TimeInterval
        else { return nil }
        return Reminder(
            blockID: block, pageID: page, date: Date(timeIntervalSince1970: date),
            text: userInfo["text"] as? String ?? "", pageTitle: userInfo["pageTitle"] as? String ?? ""
        )
    }
}

/// Ersatz im Speicher: Test-Stores planen nie Mitteilungen des Macs, denn Debug-Builds
/// haben dieselbe Kennung wie die echte App.
actor MemoryReminderCenter: ReminderCenter {
    private(set) var reminders: [UUID: Reminder] = [:]
    /// Antwort auf die Frage nach der Erlaubnis.
    private var allowed: Bool
    private(set) var authorizations = 0

    init(allowed: Bool = true) {
        self.allowed = allowed
    }

    func authorize() -> Bool {
        authorizations += 1
        return allowed
    }

    func pending() -> [Reminder] {
        let now = Date.now
        return reminders.values.filter { $0.date > now }
    }

    func schedule(_ reminder: Reminder) {
        reminders[reminder.blockID] = reminder
    }

    func cancel(_ blockIDs: [UUID]) {
        for id in blockIDs { reminders[id] = nil }
    }
}
