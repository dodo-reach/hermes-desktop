import Foundation

struct ConnectionProfile: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var label: String
    var sshAlias: String
    var sshHost: String
    var sshPort: Int?
    var sshUser: String
    var prefersMosh: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        label: String = "",
        sshAlias: String = "",
        sshHost: String = "",
        sshPort: Int? = nil,
        sshUser: String = "",
        prefersMosh: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.sshAlias = sshAlias
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.prefersMosh = prefersMosh
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastConnectedAt = lastConnectedAt
    }

    var trimmedAlias: String? {
        let value = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var trimmedHost: String? {
        let value = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var trimmedUser: String? {
        let value = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var effectiveTarget: String {
        trimmedAlias ?? trimmedHost ?? ""
    }

    var usesAliasSourceOfTruth: Bool {
        trimmedAlias != nil && trimmedHost == nil
    }

    var resolvedPort: Int? {
        guard let sshPort, sshPort > 0 else { return nil }
        if usesAliasSourceOfTruth && sshPort == 22 {
            return nil
        }
        return sshPort
    }

    var displayDestination: String {
        guard let user = trimmedUser else {
            return effectiveTarget
        }
        return "\(user)@\(effectiveTarget)"
    }

    var isValid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !effectiveTarget.isEmpty
    }

    func updated() -> ConnectionProfile {
        var copy = self
        copy.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshAlias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshUser = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sshPort = sshPort, sshPort <= 0 {
            copy.sshPort = nil
        }
        copy.updatedAt = Date()
        return copy
    }
}
