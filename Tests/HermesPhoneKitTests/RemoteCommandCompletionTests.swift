import Foundation
import Testing

@testable import HermesPhoneKit

struct RemoteCommandCompletionTests {
    @Test
    func parsesAndRemovesOnlyTheMatchingCompletionMarker() {
        let parsed = RemoteCommandCompletion.parse(
            stderr: "warning\n__HERMES_COMMAND_COMPLETE_other__:9\n__HERMES_COMMAND_COMPLETE_token__:17\n",
            token: "token"
        )

        #expect(parsed?.exitCode == 17)
        #expect(parsed?.stderr == "warning\n__HERMES_COMMAND_COMPLETE_other__:9")
    }

    @Test
    func rejectsOutputWithoutACompletionMarker() {
        #expect(RemoteCommandCompletion.parse(stderr: "", token: "missing") == nil)
        #expect(RemoteCommandCompletion.parse(stderr: "connection closed", token: "missing") == nil)
    }

    @Test
    func wrappedCommandKeepsLargeInputOutOfTheSSHExecRequest() {
        let secretPayload = String(repeating: "private-script-content", count: 8_000)
        let command = RemoteCommandCompletion.wrappedCommand(
            environmentExports: "export HERMES_HOME=\"$HOME/.hermes\"",
            remoteCommand: "python3 -",
            standardInputByteCount: secretPayload.utf8.count,
            token: "sizecheck"
        )

        #expect(!command.contains(secretPayload))
        #expect(command.utf8.count < 4_000)
        #expect(command.contains("\(secretPayload.utf8.count)"))
    }

    @Test
    func exactLengthInputRunnerExecutesLargePythonPayloadAndConfirmsCompletion() throws {
        let padding = String(repeating: "# padding for transport regression coverage\n", count: 4_000)
        let script = padding + #"import json; print(json.dumps({"ok": True, "bytes": 160000}))"# + "\n"
        let token = "integration"
        let command = RemoteCommandCompletion.wrappedCommand(
            environmentExports: "export HERMES_HOME=\"$HOME/.hermes\"",
            remoteCommand: "python3 -",
            standardInputByteCount: script.utf8.count,
            token: token
        )

        let result = try runShell(command: command, standardInput: Data(script.utf8))
        let parsed = RemoteCommandCompletion.parse(stderr: result.stderr, token: token)

        #expect(result.processExitCode == 0)
        #expect(parsed?.exitCode == 0)
        #expect(parsed?.stderr == "")
        #expect(result.stdout.contains(#""ok": true"#))
    }

    @Test
    func truncatedInputProducesFailureButStillConfirmsTheShellExit() throws {
        let token = "truncated"
        let command = RemoteCommandCompletion.wrappedCommand(
            environmentExports: "export HERMES_HOME=\"$HOME/.hermes\"",
            remoteCommand: "python3 -",
            standardInputByteCount: 100,
            token: token
        )

        let result = try runShell(command: command, standardInput: Data("short".utf8))
        let parsed = RemoteCommandCompletion.parse(stderr: result.stderr, token: token)

        #expect(result.processExitCode != 0)
        #expect(parsed?.exitCode != 0)
        #expect(parsed?.stderr.contains("EOFError") == true)
    }

    private func runShell(
        command: String,
        standardInput: Data
    ) throws -> (stdout: String, stderr: String, processExitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(standardInput)
        try inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        let stdout = String(
            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let stderr = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return (stdout, stderr, process.terminationStatus)
    }
}
