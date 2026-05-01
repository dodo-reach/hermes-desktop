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
        #expect(profile.remotePath(for: .memory) == "~/.hermes/memories/MEMORY.md")
        #expect(
            profile.remoteShellBootstrapCommand ==
                "export HERMES_HOME=\"$HOME/.hermes\"; exec \"${SHELL:-/bin/zsh}\" -l"
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
        #expect(
            profileScoped.remoteShellBootstrapCommand ==
                "export HERMES_HOME=\"$HOME/.hermes/profiles/researcher\"; exec \"${SHELL:-/bin/zsh}\" -l"
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
                "export HERMES_HOME=\"$HOME/.hermes/profiles/research\\\"lab\"; exec \"${SHELL:-/bin/zsh}\" -l"
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
