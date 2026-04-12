import Foundation

struct SSHCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum SSHTransportError: LocalizedError {
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
            message
        }
    }
}

final class SSHTransport: @unchecked Sendable {
    private let paths: AppPaths

    init(paths: AppPaths) {
        self.paths = paths
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
            allocateTTY: allocateTTY
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
        sshArguments(for: connection, remoteCommand: nil, allocateTTY: true)
    }

    func moshArguments(for connection: ConnectionProfile) -> [String] {
        var args: [String] = []

        // Pass custom SSH port through mosh's --ssh flag
        if let port = connection.resolvedPort {
            args += ["--ssh=ssh -p \(port)"]
        }

        // user@host or just host
        if let user = connection.trimmedUser {
            args.append("\(user)@\(connection.effectiveTarget)")
        } else {
            args.append(connection.effectiveTarget)
        }

        return args
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
        allocateTTY: Bool
    ) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=300",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "ControlPath=\(paths.controlPath(for: connection))"
        ]

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

                guard state.claimResume() else { return }
                continuation.resume(returning: result)
            }

            do {
                try process.run()
                if let standardInput,
                   let pipe = process.standardInput as? Pipe {
                    pipe.fileHandleForWriting.write(standardInput)
                    try? pipe.fileHandleForWriting.close()
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
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String,
              !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return error
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
