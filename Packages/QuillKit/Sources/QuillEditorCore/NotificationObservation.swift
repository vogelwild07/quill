import Foundation

/// Beobachtung über `NotificationCenter`, die sich beim Freigeben selbst abmeldet.
/// Blockbasierte Beobachter bleiben sonst registriert, auch wenn ihr Besitzer weg ist.
package final class NotificationObservation {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    package init(
        _ name: Notification.Name,
        object: AnyObject?,
        center: NotificationCenter = .default,
        queue: OperationQueue? = .main,
        using block: @escaping @Sendable (Notification) -> Void
    ) {
        self.center = center
        token = center.addObserver(forName: name, object: object, queue: queue, using: block)
    }

    deinit {
        center.removeObserver(token)
    }
}
