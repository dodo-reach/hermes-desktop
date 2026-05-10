import Foundation
import Testing
@testable import HermesDesktop

struct ConnectionProfileTests {
    @Test
    func defaultProfileUsesCanonicalPathsAndAliasDrivenDefaults() {
        let profile = ConnectionProfile(
            label: "  Home  ",
            sshAlias: "  hermes-home  ",
            sshHost: "",
            sshPort: 22,
            sshUser: "  alice  ",
            hermesProfile: " default "
        ).updated()

        #expect(profile.trimmedHermesProfile == nil)
        #expect(profile.resolvedHermesProfileName == "default")
        #expect(profile.remoteHermesHomePath == "~/.hermes")
        #expect(profile.remoteSkillsPath == "~/.hermes/skills")
        #expect(profile.remoteCronJobsPath == "~/.hermes/cron/jobs.json")
        #expect(profile.remoteKanbanHomePath == "~/.hermes")
        #expect(profile.remoteKanbanDatabasePath == "~/.hermes/kanban.db")
        #expect(profile.remotePath(for: .memory) == "~/.hermes/memories/MEMORY.md")
        #expect(
            profile.remoteShellBootstrapCommand ==
                "exec /bin/sh -c \"export HERMES_HOME=\\\"\\$HOME/.hermes\\\"; exec \\\"\\${SHELL:-/bin/zsh}\\\" -l\""
        )
        #expect(profile.displayDestination == "alice@hermes-home")
        #expect(profile.resolvedPort == nil)
        #expect(profile.usesAliasSourceOfTruth)
        #expect(profile.label == "Home")
        #expect(profile.sshAlias == "hermes-home")
        #expect(profile.sshUser == "alice")
    }

    @Test
    func namedProfileChangesWorkspaceScopeWithoutChangingHostIdentity() {
        let base = ConnectionProfile(
            label: "Research Host",
            sshAlias: "hermes-home",
            sshPort: 2222,
            sshUser: "alice"
        ).updated()
        let profileScoped = base.applyingHermesProfile(named: "researcher")

        #expect(profileScoped.resolvedHermesProfileName == "researcher")
        #expect(profileScoped.remoteHermesHomePath == "~/.hermes/profiles/researcher")
        #expect(profileScoped.remoteKanbanHomePath == "~/.hermes")
        #expect(profileScoped.remoteKanbanDatabasePath == "~/.hermes/kanban.db")
        #expect(
            profileScoped.remoteShellBootstrapCommand ==
                "exec /bin/sh -c \"export HERMES_HOME=\\\"\\$HOME/.hermes/profiles/researcher\\\"; exec \\\"\\${SHELL:-/bin/zsh}\\\" -l\""
        )
        #expect(base.workspaceScopeFingerprint != profileScoped.workspaceScopeFingerprint)
        #expect(base.hostConnectionFingerprint == profileScoped.hostConnectionFingerprint)
        #expect(profileScoped.resolvedPort == 2222)
    }

    @Test
    func bootstrapCommandEscapesQuotesInProfileName() {
        let profile = ConnectionProfile(
            label: "Quoted",
            sshHost: "example.com",
            sshUser: "alice",
            hermesProfile: "research\"lab"
        ).updated()

        #expect(
            profile.remoteShellBootstrapCommand ==
                "exec /bin/sh -c \"export HERMES_HOME=\\\"\\$HOME/.hermes/profiles/research\\\\\\\"lab\\\"; exec \\\"\\${SHELL:-/bin/zsh}\\\" -l\""
        )
    }

    @Test
    func bootstrapCommandEscapesShellExpansionInProfileName() {
        let profile = ConnectionProfile(
            label: "Shell Expansion",
            sshHost: "example.com",
            sshUser: "alice",
            hermesProfile: "research$HOME`whoami`"
        ).updated()

        #expect(
            profile.remoteShellBootstrapCommand ==
                "exec /bin/sh -c \"export HERMES_HOME=\\\"\\$HOME/.hermes/profiles/research\\\\\\$HOME\\\\`whoami\\\\`\\\"; exec \\\"\\${SHELL:-/bin/zsh}\\\" -l\""
        )
    }

    @Test
    func rejectsUnsafeSSHArguments() {
        let dashedHost = ConnectionProfile(
            label: "Unsafe",
            sshHost: "-oProxyCommand=sh"
        ).updated()

        let spacedUser = ConnectionProfile(
            label: "Unsafe",
            sshHost: "example.com",
            sshUser: "alice bob"
        ).updated()

        #expect(dashedHost.validationError == "Host cannot start with a dash.")
        #expect(spacedUser.validationError == "SSH user cannot contain whitespace or control characters.")
    }

    @Test
    func sshValidationDoesNotRequireDisplayName() {
        let profile = ConnectionProfile(
            label: "",
            sshHost: "example.com"
        ).updated()

        #expect(profile.validationError == "Name is required.")
        #expect(profile.sshValidationError == nil)
    }

    @Test
    func rejectsHermesProfilePaths() {
        let profile = ConnectionProfile(
            label: "Unsafe",
            sshHost: "example.com",
            hermesProfile: "../prod"
        ).updated()

        #expect(profile.validationError == "Hermes profile must be a profile name, not a path.")
    }

    @Test
    func startupCommandRunsThroughLoginShellWithoutInputInjection() {
        let profile = ConnectionProfile(
            label: "Research Host",
            sshHost: "example.com",
            hermesProfile: "researcher"
        ).updated()

        #expect(
            profile.remoteShellBootstrapCommand(startupCommandLine: "hermes --profile researcher --resume 'debug session'\\''s final turn'") ==
                "exec /bin/sh -c \"export HERMES_HOME=\\\"\\$HOME/.hermes/profiles/researcher\\\"; exec \\\"\\${SHELL:-/bin/zsh}\\\" -lc \\\"hermes --profile researcher --resume 'debug session'\\\\\\\\''s final turn'\\\"\""
        )
    }

    @Test
    func startupCommandEscapesDoubleQuotedShellExpansion() {
        let profile = ConnectionProfile(
            label: "Default",
            sshHost: "example.com"
        ).updated()

        #expect(
            profile.remoteShellBootstrapCommand(startupCommandLine: "printf \"$HOME `whoami`\"") ==
                "exec /bin/sh -c \"export HERMES_HOME=\\\"\\$HOME/.hermes\\\"; exec \\\"\\${SHELL:-/bin/zsh}\\\" -lc \\\"printf \\\\\\\"\\\\\\$HOME \\\\`whoami\\\\`\\\\\\\"\\\"\""
        )
    }

    @Test
    func controlPathRecreatesTemporarySocketDirectoryWhenPruned() throws {
        let fileManager = FileManager.default
        let paths = AppPaths(fileManager: fileManager)
        try? fileManager.removeItem(at: paths.controlSocketDirectoryURL)

        let profile = ConnectionProfile(
            label: "Hermes VM",
            sshAlias: "hermes",
            sshUser: "ubuntu"
        ).updated()

        let controlPath = paths.controlPath(for: profile)

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: paths.controlSocketDirectoryURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(controlPath.hasPrefix(paths.controlSocketDirectoryURL.path))
    }
}
