#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import UserNotifications

enum HermesPhoneNotificationKind: String, Equatable, Sendable {
    case assistantReply = "assistant_reply"
    case pendingRequest = "pending_request"
    case continuation = "continuation"
}

struct HermesPhoneNotificationRoute: Equatable, Sendable {
    var kind: HermesPhoneNotificationKind
    var workspaceFingerprint: String?
    var sessionID: String?
}

private enum HermesPhoneNotificationUserInfoKey {
    static let source = "source"
    static let kind = "kind"
    static let workspaceFingerprint = "workspace_fingerprint"
    static let sessionID = "session_id"
}

@MainActor
final class HermesPhoneNotificationService: ObservableObject {
    static let shared = HermesPhoneNotificationService()

    @Published private(set) var pendingRoute: HermesPhoneNotificationRoute?

    private let center = UNUserNotificationCenter.current()
    private var isConfigured = false
    private var appIsActive = true
    private var conversationVisible = false
    private var visibleConversationSessionID: String?
    private var deliveredIdentifiers: [String] = []
    private var deliveredIdentifierSet = Set<String>()

    private init() {}

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        center.delegate = HermesPhoneNotificationDelegate.shared
    }

    func updateScenePhase(_ phase: ScenePhase) {
        appIsActive = phase == .active
    }

    func setConversationVisible(_ isVisible: Bool, sessionID: String?) {
        conversationVisible = isVisible
        visibleConversationSessionID = isVisible ? sessionID : nil
    }

    func updateVisibleConversationSession(_ sessionID: String?) {
        guard conversationVisible else { return }
        visibleConversationSessionID = sessionID
    }

    func requestAuthorizationIfNeeded() async {
        _ = await notificationsAreAvailable(requestIfNeeded: true)
    }

    func notifyAssistantReply(
        messageID: UUID,
        sessionID: String?,
        workspaceFingerprint: String?,
        text: String?
    ) {
        guard shouldNotify(sessionID: sessionID) else { return }

        let body = compactPreview(text) ?? "Hermes finished a response."
        scheduleNotification(
            identifier: identifier(
                kind: .assistantReply,
                workspaceFingerprint: workspaceFingerprint,
                sessionID: sessionID,
                discriminator: messageID.uuidString
            ),
            kind: .assistantReply,
            title: "Hermes replied",
            body: body,
            sessionID: sessionID,
            workspaceFingerprint: workspaceFingerprint
        )
    }

    func notifyPendingRequest(
        requestID: String,
        kindTitle: String,
        sessionID: String?,
        workspaceFingerprint: String?
    ) {
        guard shouldNotify(sessionID: sessionID) else { return }

        scheduleNotification(
            identifier: identifier(
                kind: .pendingRequest,
                workspaceFingerprint: workspaceFingerprint,
                sessionID: sessionID,
                discriminator: requestID
            ),
            kind: .pendingRequest,
            title: "Hermes needs input",
            body: kindTitle,
            sessionID: sessionID,
            workspaceFingerprint: workspaceFingerprint
        )
    }

    func notifyContinuation(
        sessionID: String?,
        workspaceFingerprint: String?,
        message: String?
    ) {
        guard shouldNotify(sessionID: sessionID) else { return }

        scheduleNotification(
            identifier: identifier(
                kind: .continuation,
                workspaceFingerprint: workspaceFingerprint,
                sessionID: sessionID,
                discriminator: sessionID ?? UUID().uuidString
            ),
            kind: .continuation,
            title: "Hermes continued the chat",
            body: compactPreview(message) ?? "The active conversation continued in a new session.",
            sessionID: sessionID,
            workspaceFingerprint: workspaceFingerprint
        )
    }

    func handleNotificationRoute(_ route: HermesPhoneNotificationRoute?) {
        guard let route else { return }
        pendingRoute = route
    }

    func consumePendingRoute(_ route: HermesPhoneNotificationRoute) {
        guard pendingRoute == route else { return }
        pendingRoute = nil
    }

    private func scheduleNotification(
        identifier: String,
        kind: HermesPhoneNotificationKind,
        title: String,
        body: String,
        sessionID: String?,
        workspaceFingerprint: String?
    ) {
        guard rememberIdentifier(identifier) else { return }

        Task { [weak self] in
            guard let self else { return }
            guard await self.notificationsAreAvailable(requestIfNeeded: true) else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = self.threadIdentifier(
                workspaceFingerprint: workspaceFingerprint,
                sessionID: sessionID
            )
            content.categoryIdentifier = "HERMES_CHAT"
            content.userInfo = self.userInfo(
                kind: kind,
                workspaceFingerprint: workspaceFingerprint,
                sessionID: sessionID
            )

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    private func notificationsAreAvailable(requestIfNeeded: Bool) async -> Bool {
        configure()
        let authorizationStatus = await currentAuthorizationStatus()

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined where requestIfNeeded:
            return await requestAuthorization()
        default:
            return false
        }
    }

    private func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func shouldNotify(sessionID: String?) -> Bool {
        if !appIsActive { return true }
        guard conversationVisible else { return true }
        guard let sessionID, let visibleConversationSessionID else { return false }
        return sessionID != visibleConversationSessionID
    }

    private func rememberIdentifier(_ identifier: String) -> Bool {
        guard !deliveredIdentifierSet.contains(identifier) else { return false }
        deliveredIdentifierSet.insert(identifier)
        deliveredIdentifiers.append(identifier)

        if deliveredIdentifiers.count > 200 {
            let overflow = deliveredIdentifiers.count - 200
            let removed = deliveredIdentifiers.prefix(overflow)
            deliveredIdentifiers.removeFirst(overflow)
            for identifier in removed {
                deliveredIdentifierSet.remove(identifier)
            }
        }

        return true
    }

    private func identifier(
        kind: HermesPhoneNotificationKind,
        workspaceFingerprint: String?,
        sessionID: String?,
        discriminator: String
    ) -> String {
        [
            "hermes",
            kind.rawValue,
            sanitizedIdentifierComponent(workspaceFingerprint ?? "workspace"),
            sanitizedIdentifierComponent(sessionID ?? "session"),
            sanitizedIdentifierComponent(discriminator)
        ].joined(separator: ".")
    }

    private func threadIdentifier(workspaceFingerprint: String?, sessionID: String?) -> String {
        [
            "hermes-chat",
            sanitizedIdentifierComponent(workspaceFingerprint ?? "workspace"),
            sanitizedIdentifierComponent(sessionID ?? "session")
        ].joined(separator: ".")
    }

    private func userInfo(
        kind: HermesPhoneNotificationKind,
        workspaceFingerprint: String?,
        sessionID: String?
    ) -> [String: String] {
        var info = [
            HermesPhoneNotificationUserInfoKey.source: "hermes_phone",
            HermesPhoneNotificationUserInfoKey.kind: kind.rawValue
        ]
        if let workspaceFingerprint {
            info[HermesPhoneNotificationUserInfoKey.workspaceFingerprint] = workspaceFingerprint
        }
        if let sessionID {
            info[HermesPhoneNotificationUserInfoKey.sessionID] = sessionID
        }
        return info
    }

    private func compactPreview(_ text: String?) -> String? {
        let compact = HermesGatewayTextSanitizer.sanitize(text ?? "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !compact.isEmpty else { return nil }
        guard compact.count > 160 else { return compact }
        return String(compact.prefix(157)) + "..."
    }

    private func sanitizedIdentifierComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
    }
}

private final class HermesPhoneNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor static let shared = HermesPhoneNotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let route = notificationRoute(from: userInfo)
        Task { @MainActor in
            HermesPhoneNotificationService.shared.handleNotificationRoute(route)
        }
        completionHandler()
    }

    private func notificationRoute(from userInfo: [AnyHashable: Any]) -> HermesPhoneNotificationRoute? {
        guard userInfo[HermesPhoneNotificationUserInfoKey.source] as? String == "hermes_phone",
              let rawKind = userInfo[HermesPhoneNotificationUserInfoKey.kind] as? String,
              let kind = HermesPhoneNotificationKind(rawValue: rawKind) else {
            return nil
        }

        return HermesPhoneNotificationRoute(
            kind: kind,
            workspaceFingerprint: userInfo[HermesPhoneNotificationUserInfoKey.workspaceFingerprint] as? String,
            sessionID: userInfo[HermesPhoneNotificationUserInfoKey.sessionID] as? String
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let isHermesNotification = notification.request.content.userInfo[HermesPhoneNotificationUserInfoKey.source] as? String == "hermes_phone"
        completionHandler(isHermesNotification ? [.banner, .list, .sound] : [])
    }
}
#endif
