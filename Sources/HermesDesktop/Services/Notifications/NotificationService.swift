import AppKit
@preconcurrency import UserNotifications

@MainActor
final class NotificationService: NSObject {
    private let notificationCenter: UNUserNotificationCenter
    private var isAuthorized = false
    private var unreadCount = 0

    /// When enabled, notification banners are shown even while the app is frontmost.
    var showInAppBanners = true

    /// Controls whether notification sounds are played.
    var soundEnabled = true

    /// Whether message notifications are enabled at all.
    var messageNotificationsEnabled = true

    /// Whether approval request notifications are enabled at all.
    var approvalNotificationsEnabled = true

    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        super.init()
        notificationCenter.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard !isAuthorized else { return }
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        let center = notificationCenter
        do {
            isAuthorized = try await center.requestAuthorization(options: options)
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Posting

    func postMessageNotification(sessionTitle: String?, preview: String) {
        guard isAuthorized, messageNotificationsEnabled else { return }

        unreadCount += 1

        let content = UNMutableNotificationContent()
        content.title = sessionTitle ?? L10n.string("Hermes Agent")
        content.body = String(preview.prefix(200))
        content.badge = NSNumber(value: unreadCount)
        if soundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "message-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
        updateDockBadge()
    }

    func postApprovalNotification() {
        guard isAuthorized, approvalNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.string("Approval Required")
        content.body = L10n.string("Hermes Agent is waiting for your approval to continue.")
        if soundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "approval-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }

    // MARK: - Badge

    func clearBadge() {
        unreadCount = 0
        NSApp.dockTile.badgeLabel = nil
        notificationCenter.removeAllDeliveredNotifications()
    }

    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = unreadCount > 0 ? "\(unreadCount)" : nil
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let flags = await MainActor.run { [weak self] in
            (
                showInApp: self?.showInAppBanners ?? false,
                sound: self?.soundEnabled ?? false
            )
        }
        guard flags.showInApp else { return [] }
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if flags.sound {
            options.insert(.sound)
        }
        return options
    }
}
