#if !canImport(UIKit)
@preconcurrency import Citadel
import Foundation
import NIOCore
import Security

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
}

final class SSHTransport: @unchecked Sendable {
    func execute(
        on connection: ConnectionProfile,
        remoteCommand: String,
        standardInput: Data? = nil,
        allocateTTY _: Bool
    ) async throws -> SSHCommandResult {
        let credentialStore = ConnectionSecretsStore()
        guard let credential = try credentialStore.load(for: connection.id) else {
            throw HermesPhoneStoreError.missingCredential
        }

        let client = try await makeClient(connection: connection, credential: credential)
        defer {
            Task {
                try? await client.close()
            }
        }

        let wrapped = makeWrappedCommand(
            for: connection,
            remoteCommand: remoteCommand,
            standardInput: standardInput
        )

        var stdout = ByteBuffer()
        var stderr = ByteBuffer()
        var exitCode: Int32 = 0

        do {
            let streams = try await client.executeCommandPair(wrapped)
            async let stdoutResult = collectBuffer(from: streams.stdout)
            async let stderrResult = collectBuffer(from: streams.stderr)
            let (collectedStdout, collectedStderr) = await (stdoutResult, stderrResult)
            stdout = collectedStdout.buffer
            stderr = collectedStderr.buffer
            exitCode = collectedStdout.exitCode ?? collectedStderr.exitCode ?? 0
        } catch {
            throw mapConnectionError(error, connection: connection)
        }

        return SSHCommandResult(
            stdout: String(buffer: stdout),
            stderr: String(buffer: stderr),
            exitCode: exitCode
        )
    }

    func executeJSON<Response: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType _: Response.Type
    ) async throws -> Response {
        let result = try await execute(
            on: connection,
            remoteCommand: "python3 -",
            standardInput: Data(pythonScript.utf8),
            allocateTTY: false
        )

        try validateSuccessfulExit(result, for: connection)

        return try RemoteJSONResponseDecoder.decode(
            Response.self,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    func executeJSONLines<Response: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType _: Response.Type,
        onLine: @escaping @Sendable (Response) async throws -> Void
    ) async throws {
        let credentialStore = ConnectionSecretsStore()
        guard let credential = try credentialStore.load(for: connection.id) else {
            throw HermesPhoneStoreError.missingCredential
        }

        let client = try await makeClient(connection: connection, credential: credential)
        defer { Task { try? await client.close() } }

        let wrapped = makeWrappedCommand(
            for: connection,
            remoteCommand: "python3 -",
            standardInput: Data(pythonScript.utf8)
        )
        let decoder = JSONDecoder()
        var stdoutRemainder = ""
        var stderr = ByteBuffer()
        var exitCode: Int32 = 0

        func consumeStdout(_ chunk: ByteBuffer) async throws {
            guard let text = chunk.getString(at: chunk.readerIndex, length: chunk.readableBytes), !text.isEmpty else {
                return
            }
            stdoutRemainder.append(text)
            while let newlineRange = stdoutRemainder.range(of: "\n") {
                let line = String(stdoutRemainder[..<newlineRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutRemainder.removeSubrange(stdoutRemainder.startIndex ... newlineRange.lowerBound)
                guard !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8) else {
                    throw SSHTransportError.invalidResponse("Remote stream line was not valid UTF-8.")
                }
                do {
                    try await onLine(decoder.decode(Response.self, from: data))
                } catch let transportError as SSHTransportError {
                    throw transportError
                } catch {
                    throw SSHTransportError.invalidResponse("Failed to decode remote JSON stream line: \(error.localizedDescription)\n\nline:\n\(shortenedOutputPreview(line, limit: 2000))")
                }
            }
        }

        do {
            let streams = try await client.executeCommandPair(wrapped)
            async let stderrResult = collectBuffer(from: streams.stderr)
            do {
                for try await chunk in streams.stdout {
                    try await consumeStdout(chunk)
                }
                let line = stdoutRemainder.trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutRemainder.removeAll(keepingCapacity: false)
                if !line.isEmpty {
                    guard let data = line.data(using: .utf8) else {
                        throw SSHTransportError.invalidResponse("Remote stream line was not valid UTF-8.")
                    }
                    try await onLine(try decoder.decode(Response.self, from: data))
                }
            } catch let failure as SSHClient.CommandFailed {
                exitCode = Int32(failure.exitCode)
            }
            let collectedStderr = await stderrResult
            stderr = collectedStderr.buffer
            exitCode = exitCode == 0 ? (collectedStderr.exitCode ?? 0) : exitCode
        } catch let failure as SSHClient.CommandFailed {
            exitCode = Int32(failure.exitCode)
        } catch {
            throw mapConnectionError(error, connection: connection)
        }

        try validateSuccessfulExit(
            SSHCommandResult(stdout: "", stderr: String(buffer: stderr), exitCode: exitCode),
            for: connection
        )
    }

    private func formattedInvalidJSONResponse(
        stdout: String,
        stderr: String,
        decodingError: Error
    ) -> String {
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if looksLikeNonJSONShellOutput(trimmedStdout) {
            let guidance = "Remote command returned non-JSON output. This usually means a shell startup file or gateway bootstrap printed text during a non-interactive SSH command. Keep startup files quiet for non-interactive SSH sessions and retry."
            let preview = shortenedOutputPreview(trimmedStdout)
            if preview.isEmpty {
                return guidance
            }
            return "\(guidance)\n\nPreview:\n\(preview)"
        }

        var message = "Failed to decode remote JSON: \(decodingErrorDescription(decodingError))"
        if !trimmedStdout.isEmpty {
            message += "\n\nstdout:\n\(shortenedOutputPreview(trimmedStdout, limit: 2000))"
        }
        if !trimmedStderr.isEmpty {
            message += "\n\nstderr:\n\(shortenedOutputPreview(trimmedStderr, limit: 2000))"
        }
        return message
    }

    private func decodingErrorDescription(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            let path: String
            switch decodingError {
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context), .dataCorrupted(let context):
                path = context.codingPath.map(\.stringValue).joined(separator: ".")
            @unknown default:
                path = ""
            }
            let base = error.localizedDescription
            return path.isEmpty ? base : "\(base) at \(path)"
        }
        return error.localizedDescription
    }

    private func looksLikeNonJSONShellOutput(_ output: String) -> Bool {
        guard let firstCharacter = output.first else { return false }
        if firstCharacter == "{" || firstCharacter == "[" {
            return false
        }

        let lowered = output.lowercased()
        return output.contains("{") ||
            output.contains("[") ||
            lowered.contains("welcome") ||
            lowered.contains("last login")
    }

    private func shortenedOutputPreview(_ output: String, limit: Int = 240) -> String {
        guard output.count > limit else { return output }
        let endIndex = output.index(output.startIndex, offsetBy: limit)
        return String(output[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func validateSuccessfulExit(_ result: SSHCommandResult, for connection: ConnectionProfile? = nil) throws {
        guard result.exitCode == 0 else {
            throw SSHTransportError.remoteFailure(
                describeRemoteFailure(
                    stdout: result.stdout,
                    stderr: result.stderr,
                    exitCode: result.exitCode,
                    connection: connection
                )
            )
        }
    }

    func describeRemoteFailure(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        connection _: ConnectionProfile?
    ) -> String {
        let rawMessage = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let lowered = rawMessage.lowercased()
        if lowered.contains("permission denied") {
            return "SSH authentication failed. Verify the selected user and credentials."
        }
        if lowered.contains("host key verification failed") {
            return "SSH host key verification failed."
        }
        if lowered.contains("python3: command not found") {
            return "SSH succeeded, but python3 is not available on the remote host."
        }
        if !rawMessage.isEmpty {
            return rawMessage
        }
        return "SSH command failed with exit code \(exitCode)."
    }

    func makeClient(connection: ConnectionProfile, credential: SSHCredentialRecord) async throws -> SSHClient {
        let authMethod = try connection.authenticationMethod(using: credential)
        let settings = SSHClientSettings(
            host: connection.effectiveTarget,
            port: connection.resolvedPort ?? 22,
            authenticationMethod: { authMethod },
            hostKeyValidator: .custom(
                ConnectionHostKeyValidator(
                    connection: connection,
                    trustStore: HostKeyTrustStore()
                )
            )
        )

        do {
            return try await SSHClient.connect(to: settings)
        } catch {
            throw mapConnectionError(error, connection: connection)
        }
    }

    func makeWrappedCommand(
        for connection: ConnectionProfile,
        remoteCommand: String,
        standardInput: Data?
    ) -> String {
        var commandBody = remoteCommand
        if let standardInput, let inputText = String(data: standardInput, encoding: .utf8) {
            let marker = "__HERMES_STDIN__"
            commandBody = "\(remoteCommand) <<'\(marker)'\n\(inputText)\n\(marker)"
        }

        let fullBody = "\(connection.remoteServiceEnvironmentExports); \(commandBody)"
        return "/bin/sh -lc \(fullBody.shellQuotedForTerminalCommand)"
    }

    private func mapConnectionError(_ error: Error, connection: ConnectionProfile) -> Error {
        if let hostKeyError = error as? HostKeyValidationError {
            return hostKeyError
        }

        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("password") {
            return SSHTransportError.invalidConnection("SSH authentication failed for \(connection.displayDestination).")
        }
        if message.localizedCaseInsensitiveContains("publickey") {
            return SSHTransportError.invalidConnection("SSH private key authentication failed for \(connection.displayDestination).")
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return SSHTransportError.remoteFailure("The SSH connection to \(connection.displayDestination) timed out.")
        }
        return SSHTransportError.launchFailure(message)
    }

    private func collectBuffer(
        from stream: AsyncThrowingStream<ByteBuffer, Error>
    ) async -> (buffer: ByteBuffer, exitCode: Int32?) {
        var buffer = ByteBuffer()
        do {
            for try await chunk in stream {
                buffer.writeImmutableBuffer(chunk)
            }
            return (buffer, nil)
        } catch let failure as SSHClient.CommandFailed {
            return (buffer, Int32(failure.exitCode))
        } catch {
            return (buffer, nil)
        }
    }
}
#endif
