#if canImport(AppKit)
import AppKit
import UserNotifications

/// Klick auf eine Erinnerung öffnet die Seite; Mitteilungen erscheinen auch, wenn Quill
/// vorn ist (15.4, ADR-033). Nur für den echten Store.
public final class ReminderNotifications: NSObject, UNUserNotificationCenterDelegate, Sendable {
    public static let shared = ReminderNotifications()

    /// Vor dem Ende des Starts, damit auch ein Klick, der Quill startet, ankommt.
    @MainActor
    public func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let pageID = SystemReminderCenter.pageID(response.notification.request.content.userInfo) else { return }
        await MainActor.run { PageJumpRouter.shared.open(pageID) }
    }
}
#endif
