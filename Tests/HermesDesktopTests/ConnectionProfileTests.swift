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
                #"exec /bin/sh -c "export HERMES_HOME=\"\$HOME/.hermes\"; export PATH=\"\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"; exec \"\${SHELL:-/bin/zsh}\" -l""#
        )
        #expect(profile.cliHermesProfileName == nil)
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
        #expect(profileScoped.cliHermesProfileName == "researcher")
        #expect(profileScoped.remoteKanbanHomePath == "~/.hermes")
        #expect(profileScoped.remoteKanbanDatabasePath == "~/.hermes/kanban.db")
        #expect(
            profileScoped.remoteShellBootstrapCommand ==
                #"exec /bin/sh -c "export HERMES_HOME=\"\$HOME/.hermes/profiles/researcher\"; export PATH=\"\$HOME/.hermes/profiles/researcher/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"; exec \"\${SHELL:-/bin/zsh}\" -l""#
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
                #"exec /bin/sh -c "export HERMES_HOME=\"\$HOME/.hermes/profiles/research\\\"lab\"; export PATH=\"\$HOME/.hermes/profiles/research\\\"lab/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"; exec \"\${SHELL:-/bin/zsh}\" -l""#
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
                #"exec /bin/sh -c "export HERMES_HOME=\"\$HOME/.hermes/profiles/research\\\$HOME\\\`whoami\\\`\"; export PATH=\"\$HOME/.hermes/profiles/research\\\$HOME\\\`whoami\\\`/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"; exec \"\${SHELL:-/bin/zsh}\" -l""#
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
    func customHermesHomePathOverridesStandardWorkspaceWithoutChangingHostIdentity() {
        let profile = ConnectionProfile(
            label: "Container Host",
            sshHost: "example.com",
            sshUser: "alice",
            customHermesHomePath: "  ~/.hermes-work/  "
        ).updated()

        #expect(profile.trimmedHermesProfile == nil)
        #expect(profile.trimmedCustomHermesHomePath == "~/.hermes-work")
        #expect(profile.usesCustomHermesHome)
        #expect(profile.usesDefaultHermesProfile == false)
        #expect(profile.cliHermesProfileName == nil)
        #expect(profile.resolvedHermesProfileName == ".hermes-work")
        #expect(profile.remoteHermesHomePath == "~/.hermes-work")
        #expect(profile.remoteShellBootstrapCommand == #"exec /bin/sh -c "export HERMES_HOME=\"\$HOME/.hermes-work\"; export PATH=\"\$HOME/.hermes-work/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"; exec \"\${SHELL:-/bin/zsh}\" -l""#)
    }

    @Test
    func customHermesHomePathSupportsAbsoluteRemotePaths() {
        let profile = ConnectionProfile(
            label: "Container Host",
            sshHost: "example.com",
            customHermesHomePath: "/opt/data/hermes agent"
        ).updated()

        #expect(profile.remoteHermesHomePath == "/opt/data/hermes agent")
        #expect(
            profile.remoteShellBootstrapCommand ==
                #"exec /bin/sh -c "export HERMES_HOME=\"/opt/data/hermes agent\"; export PATH=\"/opt/data/hermes agent/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"; exec \"\${SHELL:-/bin/zsh}\" -l""#
        )
        #expect(profile.resolvedHermesProfileName == "hermes agent")
    }

    @Test
    func rejectsSimultaneousProfileAndCustomHermesHomePath() {
        let profile = ConnectionProfile(
            label: "Unsafe",
            sshHost: "example.com",
            hermesProfile: "research",
            customHermesHomePath: "~/.hermes-work"
        ).updated()

        #expect(profile.validationError == "Choose either a Hermes profile or a custom Hermes home path.")
    }

    @Test
    func rejectsUnsupportedCustomHermesHomePathFormats() {
        let relativeProfile = ConnectionProfile(
            label: "Unsafe",
            sshHost: "example.com",
            customHermesHomePath: "profiles/work"
        ).updated()

        let envProfile = ConnectionProfile(
            label: "Unsafe",
            sshHost: "example.com",
            customHermesHomePath: "$HOME/.hermes-work"
        ).updated()

        #expect(relativeProfile.validationError == "Custom Hermes home must start with `~/` or `/`.")
        #expect(envProfile.validationError == "Custom Hermes home must start with `~/` or `/`.")
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
                #"exec /bin/sh -c "export HERMES_HOME=\"\$HOME/.hermes/profiles/researcher\"; export PATH=\"\$HOME/.hermes/profiles/researcher/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"; exec \"\${SHELL:-/bin/zsh}\" -lc \"hermes --profile researcher --resume 'debug session'\\\\''s final turn'; hermes_bootstrap_exit_code=\\\$?; if [ \\\"\\\$hermes_bootstrap_exit_code\\\" -ne 0 ]; then printf '\\\\n[Hermes Desktop] Startup command exited with status %s.\\\\n' \\\"\\\$hermes_bootstrap_exit_code\\\"; fi; exec \\\"\\\${SHELL:-/bin/zsh}\\\" -l\"""#
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
                #"exec /bin/sh -c "export HERMES_HOME=\"\$HOME/.hermes\"; export PATH=\"\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"; exec \"\${SHELL:-/bin/zsh}\" -lc \"printf \\\"\\\$HOME \\\`whoami\\\`\\\"; hermes_bootstrap_exit_code=\\\$?; if [ \\\"\\\$hermes_bootstrap_exit_code\\\" -ne 0 ]; then printf '\\\\n[Hermes Desktop] Startup command exited with status %s.\\\\n' \\\"\\\$hermes_bootstrap_exit_code\\\"; fi; exec \\\"\\\${SHELL:-/bin/zsh}\\\" -l\"""#
        )
    }

    @Test
    func serviceCommandUsesNonLoginShellToPreservePreparedPath() {
        let profile = ConnectionProfile(
            label: "Default",
            sshHost: "example.com"
        ).updated()

        let command = profile.remoteServiceCommand("python3 -m tui_gateway.entry")

        #expect(command.contains(#"export HERMES_HOME=\"\$HOME/.hermes\""#))
        #expect(command.contains(#"export PATH=\"\$HOME/.hermes/hermes-agent/venv/bin:\$HOME/.local/bin:\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\""#))
        #expect(command.contains(#"exec /bin/sh -c \"python3 -m tui_gateway.entry\""#))
        #expect(!command.contains("exec /bin/sh -lc"))
    }

    @Test
    func wrappedBootstrapCanRunUnderPOSIXOuterShell() throws {
        let profile = ConnectionProfile(
            label: "Default",
            sshHost: "example.com"
        ).updated()

        let result = try runBootstrapLocally(
            profile.remoteShellBootstrapCommand(startupCommandLine: #"printf "%s\n" "$HERMES_HOME""#)
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "/tmp/hermes-home/.hermes\n")
        #expect(result.stderr == "")
    }

    @Test
    func wrappedBootstrapKeepsProfileShellSyntaxLiteral() throws {
        let profile = ConnectionProfile(
            label: "Shell Expansion",
            sshHost: "example.com",
            hermesProfile: "research$HOME`whoami`"
        ).updated()

        let result = try runBootstrapLocally(
            profile.remoteShellBootstrapCommand(startupCommandLine: #"printf "%s\n" "$HERMES_HOME""#)
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "/tmp/hermes-home/.hermes/profiles/research$HOME`whoami`\n")
        #expect(result.stderr == "")
    }

    @Test
    func wrappedBootstrapExpandsCustomHermesHomePathTildeOnRemoteShell() throws {
        let profile = ConnectionProfile(
            label: "Container Host",
            sshHost: "example.com",
            customHermesHomePath: "~/.hermes-work"
        ).updated()

        let result = try runBootstrapLocally(
            profile.remoteShellBootstrapCommand(startupCommandLine: #"printf "%s\n" "$HERMES_HOME""#)
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "/tmp/hermes-home/.hermes-work\n")
        #expect(result.stderr == "")
    }

    @Test
    func wrappedBootstrapPrependsActiveHermesCLIPaths() throws {
        let profile = ConnectionProfile(
            label: "Container Host",
            sshHost: "example.com",
            customHermesHomePath: "~/.hermes-work"
        ).updated()

        let result = try runBootstrapLocally(
            profile.remoteShellBootstrapCommand(startupCommandLine: #"printf "%s\n" "$PATH""#)
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("/tmp/hermes-home/.hermes-work/hermes-agent/venv/bin"))
        #expect(result.stdout.contains("/tmp/hermes-home/.local/bin"))
        #expect(result.stdout.contains("/tmp/hermes-home/.hermes/hermes-agent/venv/bin"))
        #expect(result.stderr == "")
    }

    @Test
    func wrappedBootstrapRunsCleanlyUnderZshShell() throws {
        let profile = ConnectionProfile(
            label: "Research Host",
            sshHost: "example.com",
            hermesProfile: "researcher"
        ).updated()

        let result = try runBootstrapLocally(
            profile.remoteShellBootstrapCommand(startupCommandLine: #"printf "%s\n" "$HERMES_HOME""#),
            shellPath: "/bin/zsh"
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "/tmp/hermes-home/.hermes/profiles/researcher\n")
        #expect(result.stderr == "")
    }


    @Test
    func caelWorkspaceBaseURLDefaultsToBigMacAndBuildsRoutes() {
        let profile = ConnectionProfile(
            label: "BigMac",
            sshAlias: "bigmac-home"
        ).updated()

        #expect(profile.resolvedCaelWorkspaceBaseURL == ConnectionProfile.defaultCaelWorkspaceBaseURL)
        #expect(profile.caelWorkspaceURLString(path: "/cael-home") == "http://100.97.216.111:3077/cael-home")
        #expect(profile.caelWorkspaceURLString(path: "usage") == "http://100.97.216.111:3077/usage")
    }

    @Test
    func caelWorkspaceBaseURLNormalizesAndScopesCommandCenterClient() {
        let base = ConnectionProfile(
            label: "BigMac",
            sshAlias: "bigmac-home"
        ).updated()
        let custom = ConnectionProfile(
            label: "BigMac",
            sshAlias: "bigmac-home",
            caelWorkspaceBaseURL: "  https://cael.example.test:8443/workspace/  "
        ).updated()

        #expect(custom.resolvedCaelWorkspaceBaseURL == "https://cael.example.test:8443/workspace")
        #expect(custom.workspaceScopeFingerprint == base.workspaceScopeFingerprint)
        #expect(custom.commandCenterClientFingerprint != base.commandCenterClientFingerprint)
    }

    @Test
    func rejectsInvalidCaelWorkspaceBaseURL() {
        let missingScheme = ConnectionProfile(
            label: "Bad Workspace",
            sshHost: "example.com",
            caelWorkspaceBaseURL: "100.97.216.111:3077"
        ).updated()
        let withQuery = ConnectionProfile(
            label: "Bad Workspace",
            sshHost: "example.com",
            caelWorkspaceBaseURL: "http://100.97.216.111:3077?token=abc"
        ).updated()

        #expect(missingScheme.validationError == "Workspace URL must start with http:// or https://.")
        #expect(withQuery.validationError == "Workspace URL cannot include query strings or fragments.")
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

private struct LocalBootstrapResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private func runBootstrapLocally(
    _ command: String,
    shellPath: String = "/bin/sh"
) throws -> LocalBootstrapResult {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.environment = [
        "HOME": "/tmp/hermes-home",
        "SHELL": shellPath
    ]
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    return LocalBootstrapResult(
        stdout: stdout,
        stderr: stderr,
        exitCode: process.terminationStatus
    )
}
