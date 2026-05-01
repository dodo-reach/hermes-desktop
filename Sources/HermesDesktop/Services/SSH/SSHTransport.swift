import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "HermesDesktop",
    category: "SSHTransport"
)

struct SSHCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum SSHTransportError: LocalizedError {
    case invalidConnection(String)
    case launchFailure(String)
    case localFailure(String)
    case remoteFailure(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidConnection(let message),
             .launchFailure(let message),
             .localFailure(let message),
             .remoteFailure(let message),
             .invalidResponse(let message):
            message
        }
    }
}

final class SSHTransport: @unchecked Sendable {
    private let paths: AppPaths
    private let resolvedEnvironment: [String: String]

    private enum ConnectionPurpose {
        case service
        case terminalShell
    }

    init(paths: AppPaths) {
        self.paths = paths
        self.resolvedEnvironment = SSHTransport.buildResolvedEnvironment()
    }

    // Environment forwarded to terminal SSH subprocesses (SwiftTerm key=value format).
    var terminalEnvironment: [String] {
        var vars = ["TERM=xterm-256color", "COLORTERM=truecolor"]
        for key in ["HOME", "USER", "SSH_AUTH_SOCK", "SSH_AGENT_PID", "PATH"] {
            if let value = resolvedEnvironment[key] {
                vars.append("\(key)=\(value)")
            }
        }
        return vars
    }

    private static func buildResolvedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Always prefer the keychain file: the process environment is frozen at launch and
        // may point to a stale agent socket from a previous session.
        if let sock = keychainAuthSock() {
            logger.info("SSH_AUTH_SOCK from keychain file: \(sock, privacy: .public)")
            env["SSH_AUTH_SOCK"] = sock
        } else if let sock = env["SSH_AUTH_SOCK"] {
            logger.info("SSH_AUTH_SOCK from process environment: \(sock, privacy: .public)")
        } else {
            logger.warning("SSH_AUTH_SOCK not found in keychain files or environment — SSH agent auth will not work")
        }
        return env
    }

    // Reads SSH_AUTH_SOCK from funtoo/keychain shell files in ~/.keychain/.
    // Scans all *-sh files so hostname variations (short vs FQDN) don't matter.
    private static func keychainAuthSock() -> String? {
        let keychainDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".keychain")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: keychainDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            logger.debug("~/.keychain directory not found or unreadable")
            return nil
        }
        let shFiles = entries
            .filter { $0.lastPathComponent.hasSuffix("-sh") }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return d1 > d2
            }
        for file in shFiles {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                logger.debug("Could not read keychain file: \(file.lastPathComponent)")
                continue
            }
            for line in content.components(separatedBy: .newlines) {
                guard line.hasPrefix("SSH_AUTH_SOCK=") else { continue }
                var value = String(line.dropFirst("SSH_AUTH_SOCK=".count))
                    .components(separatedBy: ";").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                // Strip surrounding quotes written by keychain: SSH_AUTH_SOCK="/path/..."
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                if !value.isEmpty { return value }
            }
            logger.debug("No SSH_AUTH_SOCK found in keychain file: \(file.lastPathComponent)")
        }
        return nil
    }

    func execute(
        on connection: ConnectionProfile,
        remoteCommand: String,
        standardInput: Data? = nil,
        allocateTTY: Bool
    ) async throws -> SSHCommandResult {
        guard !connection.effectiveTarget.isEmpty else {
            throw SSHTransportError.invalidConnection("The SSH target is empty.")
        }

        let arguments = sshArguments(
            for: connection,
            remoteCommand: remoteCommand,
            allocateTTY: allocateTTY,
            purpose: .service
        )

        return try await runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: arguments,
            standardInput: standardInput
        )
    }

    func executeJSON<Response: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType: Response.Type
    ) async throws -> Response {
        let result = try await execute(
            on: connection,
            remoteCommand: "python3 -",
            standardInput: Data(pythonScript.utf8),
            allocateTTY: false
        )

        try validateSuccessfulExit(result, for: connection)

        guard let data = result.stdout.data(using: .utf8) else {
            throw SSHTransportError.invalidResponse("Remote output was not valid UTF-8.")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SSHTransportError.invalidResponse(
                "Failed to decode remote JSON: \(error.localizedDescription)\n\n\(result.stdout)"
            )
        }
    }

    func shellArguments(for connection: ConnectionProfile) -> [String] {
        sshArguments(
            for: connection,
            remoteCommand: connection.remoteShellBootstrapCommand,
            allocateTTY: true,
            purpose: .terminalShell
        )
    }

    func validateSuccessfulExit(_ result: SSHCommandResult, for connection: ConnectionProfile? = nil) throws {
        guard result.exitCode == 0 else {
            throw SSHTransportError.remoteFailure(
                formattedRemoteFailure(
                    stdout: result.stdout,
                    stderr: result.stderr,
                    exitCode: result.exitCode,
                    connection: connection
                )
            )
        }
    }

    private func sshArguments(
        for connection: ConnectionProfile,
        remoteCommand: String?,
        allocateTTY: Bool,
        purpose: ConnectionPurpose
    ) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3"
        ]

        switch purpose {
        case .service:
            arguments.append(contentsOf: [
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=300",
                "-o", "ControlPath=\(paths.controlPath(for: connection))"
            ])
        case .terminalShell:
            // Keep interactive terminal shells isolated from background RPC-style
            // requests so an open PTY session cannot destabilize profile reloads.
            arguments.append(contentsOf: [
                "-o", "ControlMaster=no",
                "-S", "none"
            ])
        }

        if allocateTTY {
            arguments.append("-tt")
        } else {
            arguments.append("-T")
        }

        if let port = connection.resolvedPort {
            arguments.append(contentsOf: ["-p", String(port)])
        }

        arguments.append(destination(for: connection))

        if let remoteCommand {
            arguments.append(remoteCommand)
        }

        return arguments
    }

    private func destination(for connection: ConnectionProfile) -> String {
        let target = connection.effectiveTarget
        guard let user = connection.trimmedUser else {
            return target
        }
        return "\(user)@\(target)"
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        standardInput: Data?
    ) async throws -> SSHCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading
            let state = ProcessOutputState()

            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = resolvedEnvironment
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if standardInput != nil {
                process.standardInput = Pipe()
            }

            stdoutHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    state.appendStdout(chunk)
                }
            }

            stderrHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    state.appendStderr(chunk)
                }
            }

            process.terminationHandler = { process in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                let remainingStdout = stdoutHandle.readDataToEndOfFile()
                let remainingStderr = stderrHandle.readDataToEndOfFile()
                let result = state.finalResult(
                    exitCode: process.terminationStatus,
                    remainingStdout: remainingStdout,
                    remainingStderr: remainingStderr
                )

                if process.terminationStatus != 0 {
                    logger.error("ssh exited \(process.terminationStatus, privacy: .public): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)")
                } else {
                    logger.debug("ssh exited 0")
                }

                guard state.claimResume() else { return }
                continuation.resume(returning: result)
            }

            do {
                try process.run()
                if let standardInput,
                    let pipe = process.standardInput as? Pipe {
                    pipe.fileHandleForWriting.write(standardInput)
                    do {
                        try pipe.fileHandleForWriting.close()
                    } catch {
                        stdoutHandle.readabilityHandler = nil
                        stderrHandle.readabilityHandler = nil

                        guard state.claimResume() else { return }
                        continuation.resume(
                            throwing: SSHTransportError.localFailure(
                                "Failed to finish sending input to ssh: \(error.localizedDescription)"
                            )
                        )
                    }
                }
            } catch {
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                guard state.claimResume() else { return }
                continuation.resume(throwing: SSHTransportError.launchFailure(error.localizedDescription))
            }
        }
    }

    private func formattedRemoteFailure(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        connection: ConnectionProfile?
    ) -> String {
        if let structuredError = structuredRemoteError(in: stdout) {
            return structuredError
        }
        if let structuredError = structuredRemoteError(in: stderr) {
            return structuredError
        }

        let rawMessage = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let lowered = rawMessage.lowercased()
        let target = connection?.effectiveTarget

        if lowered.contains("permission denied") {
            return "SSH authentication failed. Verify the key, SSH agent, and user for this SSH target."
        }
        if lowered.contains("host key verification failed") {
            return "SSH host key verification failed. Connect once in Terminal.app or update known_hosts before retrying."
        }
        if lowered.contains("remote host identification has changed") {
            return "The SSH host key changed for this target. Refresh the entry in known_hosts before retrying."
        }
        if lowered.contains("could not resolve hostname") || lowered.contains("name or service not known") {
            return "The SSH target could not be resolved. Check the alias, hostname, IP address, or SSH config entry in this profile."
        }
        if lowered.contains("connection refused") {
            if isLoopbackTarget(target) {
                return "The SSH server on this Mac refused the connection. If you are connecting to localhost or the same Mac, make sure SSH access is enabled and retry."
            }
            return "The SSH server refused the connection. Confirm that SSH is enabled and reachable on the target host."
        }
        if lowered.contains("operation timed out") || lowered.contains("connection timed out") {
            if isLoopbackTarget(target) {
                return "The SSH connection to this Mac timed out. If you are testing localhost or the same Mac, verify that SSH access is enabled and retry."
            }
            return "The SSH connection timed out. Check that the target host is reachable from this Mac and that your SSH route is correct."
        }
        if lowered.contains("no route to host") || lowered.contains("network is unreachable") {
            return "The SSH target is unreachable from this Mac. Check the hostname, IP address, VPN, or local network path and retry."
        }
        if lowered.contains("python3: command not found") || lowered.contains("python3: not found") {
            if isLoopbackTarget(target) {
                return "SSH succeeded, but python3 is not available in the SSH shell for this Mac. Install python3 or expose it in the non-interactive SSH environment before retrying."
            }
            return "SSH succeeded, but python3 is not available in the remote shell environment. The MVP requires python3 for discovery, file editing, and session browsing."
        }

        if !rawMessage.isEmpty {
            return rawMessage
        }

        return "SSH command failed with exit code \(exitCode)."
    }

    private func isLoopbackTarget(_ target: String?) -> Bool {
        guard let target else { return false }
        let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "localhost" ||
            normalized == "127.0.0.1" ||
            normalized == "::1" ||
            normalized.hasPrefix("localhost.")
    }

    private func structuredRemoteError(in output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(RemoteErrorPayload.self, from: data),
              let error = payload.trimmedError else {
            return nil
        }

        return error
    }
}

private struct RemoteErrorPayload: Decodable {
    let error: String?

    var trimmedError: String? {
        guard let error else { return nil }
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class ProcessOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var didResume = false

    func appendStdout(_ data: Data) {
        lock.lock()
        stdoutData.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        stderrData.append(data)
        lock.unlock()
    }

    func finalResult(exitCode: Int32, remainingStdout: Data, remainingStderr: Data) -> SSHCommandResult {
        lock.lock()
        stdoutData.append(remainingStdout)
        stderrData.append(remainingStderr)
        let result = SSHCommandResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: exitCode
        )
        lock.unlock()
        return result
    }

    func claimResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if didResume {
            return false
        }

        didResume = true
        return true
    }
}
