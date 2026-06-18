#if canImport(UIKit)
@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import Security
import SwiftUI
import UIKit

enum L10n {
    static func string(_ value: String, _ arguments: CVarArg...) -> String {
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: Locale.current, arguments: arguments)
    }
}

enum SSHCredentialKind: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password:
            "Password"
        case .privateKey:
            "Private Key"
        }
    }
}

struct SSHCredentialRecord: Codable, Equatable, Sendable {
    var password: String?
    var privateKey: String?
    var passphrase: String?
}

struct SSHCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum SSHTransportError: LocalizedError, Equatable {
    case invalidConnection(String)
    case launchFailure(String)
    case remoteFailure(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidConnection(let message),
             .launchFailure(let message),
             .remoteFailure(let message),
             .invalidResponse(let message):
            return message
        }
    }
}

struct PersistenceEnvelope: Codable {
    var activeConnectionID: UUID?
    var activeHostFingerprint: String?
    var activeProfileNameByHost: [String: String]
    var connections: [ConnectionProfile]
    var terminalWorkspace: PersistedTerminalWorkspace?
    var workspaceFileBookmarks: [WorkspaceFileBookmark] = []
    var sessionCacheByWorkspace: [String: [SessionSummary]] = [:]
    var transcriptSnapshotCacheByWorkspace: [String: [String: [SessionMessage]]] = [:]
    var hiddenProfilesByHost: [String: [String]] = [:]
    var selectedKanbanBoardByWorkspace: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case activeConnectionID
        case activeHostFingerprint
        case activeProfileNameByHost
        case connections
        case terminalWorkspace
        case workspaceFileBookmarks
        case sessionCacheByWorkspace
        case transcriptSnapshotCacheByWorkspace
        case hiddenProfilesByHost
        case selectedKanbanBoardByWorkspace
    }

    init(
        activeConnectionID: UUID?,
        activeHostFingerprint: String? = nil,
        activeProfileNameByHost: [String: String] = [:],
        connections: [ConnectionProfile],
        terminalWorkspace: PersistedTerminalWorkspace?,
        workspaceFileBookmarks: [WorkspaceFileBookmark] = [],
        sessionCacheByWorkspace: [String: [SessionSummary]] = [:],
        transcriptSnapshotCacheByWorkspace: [String: [String: [SessionMessage]]] = [:],
        hiddenProfilesByHost: [String: [String]] = [:],
        selectedKanbanBoardByWorkspace: [String: String] = [:]
    ) {
        self.activeConnectionID = activeConnectionID
        self.activeHostFingerprint = activeHostFingerprint
        self.activeProfileNameByHost = activeProfileNameByHost
        self.connections = connections
        self.terminalWorkspace = terminalWorkspace
        self.workspaceFileBookmarks = workspaceFileBookmarks
        self.sessionCacheByWorkspace = sessionCacheByWorkspace
        self.transcriptSnapshotCacheByWorkspace = transcriptSnapshotCacheByWorkspace
        self.hiddenProfilesByHost = hiddenProfilesByHost
        self.selectedKanbanBoardByWorkspace = selectedKanbanBoardByWorkspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeConnectionID = try container.decodeIfPresent(UUID.self, forKey: .activeConnectionID)
        activeHostFingerprint = try container.decodeIfPresent(String.self, forKey: .activeHostFingerprint)
        activeProfileNameByHost = try container.decodeIfPresent([String: String].self, forKey: .activeProfileNameByHost) ?? [:]
        connections = try container.decode([ConnectionProfile].self, forKey: .connections)
        terminalWorkspace = try container.decodeIfPresent(PersistedTerminalWorkspace.self, forKey: .terminalWorkspace)
        workspaceFileBookmarks = try container.decodeIfPresent([WorkspaceFileBookmark].self, forKey: .workspaceFileBookmarks) ?? []
        sessionCacheByWorkspace = try container.decodeIfPresent([String: [SessionSummary]].self, forKey: .sessionCacheByWorkspace) ?? [:]
        transcriptSnapshotCacheByWorkspace = try container.decodeIfPresent([String: [String: [SessionMessage]]].self, forKey: .transcriptSnapshotCacheByWorkspace) ?? [:]
        hiddenProfilesByHost = try container.decodeIfPresent([String: [String]].self, forKey: .hiddenProfilesByHost) ?? [:]
        selectedKanbanBoardByWorkspace = try container.decodeIfPresent([String: String].self, forKey: .selectedKanbanBoardByWorkspace) ?? [:]
    }
}

enum HermesPhoneRootTab: String, CaseIterable, Identifiable, Hashable {
    case sessions
    case kanban
    case cron
    case files
    case skills
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .kanban: "Kanban"
        case .cron: "Cron"
        case .files: "Files"
        case .skills: "Skills"
        case .terminal: "Terminal"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions: "text.bubble"
        case .kanban: "rectangle.3.group"
        case .cron: "calendar.badge.clock"
        case .files: "folder"
        case .skills: "book.closed"
        case .terminal: "terminal"
        }
    }
}

enum SessionListLoadState: Equatable {
    case idle
    case pending
    case loading
    case loaded
    case failed
}

enum HermesPhoneSessionRoute: Hashable {
    case transcript(SessionSummary)
}

enum CronOperationKind: String, Sendable {
    case runNow
    case pause
    case resume
    case delete

    var label: String {
        switch self {
        case .runNow:
            return "Running..."
        case .pause:
            return "Pausing..."
        case .resume:
            return "Resuming..."
        case .delete:
            return "Deleting..."
        }
    }
}

struct CronOperationState: Equatable, Sendable {
    let jobID: String
    let kind: CronOperationKind
}

final class ConnectionSecretsStore {
    private let service = "com.hermes.phone.credentials"

    func load(for connectionID: UUID) throws -> SSHCredentialRecord? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder().decode(SSHCredentialRecord.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw HermesPhoneStoreError.keychainFailure(status)
        }
    }

    func save(_ credential: SSHCredentialRecord, for connectionID: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw HermesPhoneStoreError.keychainFailure(addStatus)
            }
            return
        }
        throw HermesPhoneStoreError.keychainFailure(status)
    }

    func delete(for connectionID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum HermesPhoneStoreError: LocalizedError {
    case missingCredential
    case invalidPrivateKeyType(String)
    case missingTerminalConnection
    case invalidRemotePath
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Missing SSH credentials for this host."
        case .invalidPrivateKeyType(let message):
            return message
        case .missingTerminalConnection:
            return "Select a host before opening Terminal."
        case .invalidRemotePath:
            return "The remote path is empty."
        case .keychainFailure(let status):
            return "Keychain error (\(status))."
        }
    }
}
#endif
