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

    var remoteSkillsPath: String {
        "\(remoteHermesHomePath)/skills"
    }

    var remoteCronJobsPath: String {
        "\(remoteHermesHomePath)/cron/jobs.json"
    }

    var remoteKanbanHomePath: String {
        "~/.hermes"
    }

    var remoteKanbanDatabasePath: String {
        "\(remoteKanbanHomePath)/kanban.db"
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
        remoteShellBootstrapCommand()
    }

    func remoteShellBootstrapCommand(startupCommandLine: String? = nil) -> String {
        let shellHomeExpression: String
        if let trimmedHermesProfile {
            let escapedProfile = trimmedHermesProfile.escapedForDoubleQuotedShellArgument
            shellHomeExpression = "$HOME/.hermes/profiles/\(escapedProfile)"
        } else {
            shellHomeExpression = "$HOME/.hermes"
        }

        let exportCommand = "export HERMES_HOME=\"\(shellHomeExpression)\""

        let innerCommand: String
        if let startupCommandLine,
              !startupCommandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escapedStartupCommand = startupCommandLine.escapedForDoubleQuotedShellArgument
            innerCommand = "\(exportCommand); exec \"${SHELL:-/bin/zsh}\" -lc \"\(escapedStartupCommand)\""
        } else {
            innerCommand = "\(exportCommand); exec \"${SHELL:-/bin/zsh}\" -l"
        }

        // Wrap in /bin/sh via exec so the command works regardless of whether the
        // user's remote login shell is fish, bash, zsh, or any other POSIX shell.
        // Fish does not understand `export` or `${VAR:-default}` syntax, but /bin/sh
        // (POSIX) handles both. The outer "..." string is escaped for fish double-quoted
        // context so fish passes it correctly to sh -c.
        return "exec /bin/sh -c \"\(innerCommand.escapedForFishDoubleQuotedString)\""
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
        validationError == nil
    }

    var validationError: String? {
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name is required."
        }

        return sshValidationError
    }

    var sshValidationError: String? {
        guard !effectiveTarget.isEmpty else {
            return "Add an SSH alias or host."
        }

        if let error = validateSSHArgument(trimmedAlias, fieldName: "SSH alias") {
            return error
        }

        if let error = validateSSHArgument(trimmedHost, fieldName: "Host") {
            return error
        }

        if let error = validateSSHArgument(trimmedUser, fieldName: "SSH user") {
            return error
        }

        if let trimmedHermesProfile {
            if trimmedHermesProfile.contains("/") || trimmedHermesProfile == "." || trimmedHermesProfile == ".." {
                return "Hermes profile must be a profile name, not a path."
            }
            if trimmedHermesProfile.containsControlCharacter {
                return "Hermes profile contains unsupported control characters."
            }
        }

        return nil
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

private extension String {
    var escapedForDoubleQuotedShellArgument: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    /// Escapes the string for use inside a fish double-quoted ("...") string.
    /// Fish interprets `\\` as `\`, `\"` as `"`, and `\$` as a literal `$`.
    var escapedForFishDoubleQuotedString: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    var containsControlCharacter: Bool {
        unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

private func validateSSHArgument(_ value: String?, fieldName: String) -> String? {
    guard let value else { return nil }
    if value.hasPrefix("-") {
        return "\(fieldName) cannot start with a dash."
    }
    if value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
        return "\(fieldName) cannot contain whitespace or control characters."
    }
    return nil
}
