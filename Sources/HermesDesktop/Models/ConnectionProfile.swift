import Foundation

struct ConnectionProfile: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var label: String
    var sshAlias: String
    var sshHost: String
    var sshPort: Int?
    var sshUser: String
    var hermesProfile: String?
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
        hermesProfile: String? = nil,
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
        self.hermesProfile = hermesProfile
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

    var trimmedHermesProfile: String? {
        guard let hermesProfile else { return nil }
        let value = hermesProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.caseInsensitiveCompare("default") != .orderedSame else { return nil }
        return value
    }

    var resolvedHermesProfileName: String {
        trimmedHermesProfile ?? "default"
    }

    var usesDefaultHermesProfile: Bool {
        trimmedHermesProfile == nil
    }

    var remoteHermesHomePath: String {
        if let trimmedHermesProfile {
            return "~/.hermes/profiles/\(trimmedHermesProfile)"
        }

        return "~/.hermes"
    }

    var remoteSessionsPath: String {
        "\(remoteHermesHomePath)/sessions"
    }

    var remoteSkillsPath: String {
        "\(remoteHermesHomePath)/skills"
    }

    var remoteCronJobsPath: String {
        "\(remoteHermesHomePath)/cron/jobs.json"
    }

    func remotePath(for trackedFile: RemoteTrackedFile) -> String {
        "\(remoteHermesHomePath)/\(trackedFile.relativePathFromHermesHome)"
    }

    func applyingHermesProfile(named profileName: String) -> ConnectionProfile {
        var copy = self
        copy.hermesProfile = profileName
        return copy.updated()
    }

    var remoteShellBootstrapCommand: String {
        let shellHomeExpression: String
        if let trimmedHermesProfile {
            let escapedProfile = trimmedHermesProfile.replacingOccurrences(of: "\"", with: "\\\"")
            shellHomeExpression = "$HOME/.hermes/profiles/\(escapedProfile)"
        } else {
            shellHomeExpression = "$HOME/.hermes"
        }

        return "export HERMES_HOME=\"\(shellHomeExpression)\"; exec \"${SHELL:-/bin/zsh}\" -l"
    }

    var workspaceScopeFingerprint: String {
        [
            effectiveTarget,
            trimmedUser ?? "",
            resolvedPort.map(String.init) ?? "",
            remoteHermesHomePath
        ].joined(separator: "|")
    }

    var hostConnectionFingerprint: String {
        [
            effectiveTarget,
            trimmedUser ?? "",
            resolvedPort.map(String.init) ?? ""
        ].joined(separator: "|")
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
        copy.hermesProfile = trimmedHermesProfile
        if let sshPort = sshPort, sshPort <= 0 {
            copy.sshPort = nil
        }
        copy.updatedAt = Date()
        return copy
    }
}
