import AppKit

/// 把 `NSWorkspace.didWakeNotification` 轉成 `FeedClient.noteWake()`。
/// `center` 與通知名稱可注入，測試用自建 `NotificationCenter` 模擬喚醒。
public final class WakeObserver {
    private var token: NSObjectProtocol?

    public init(client: FeedClient,
                center: NotificationCenter = NSWorkspace.shared.notificationCenter,
                name: Notification.Name = NSWorkspace.didWakeNotification) {
        token = center.addObserver(forName: name, object: nil, queue: nil) { [weak client] _ in client?.noteWake() }
        self.center = center
    }
    private let center: NotificationCenter
    deinit { if let token { center.removeObserver(token) } }
}
