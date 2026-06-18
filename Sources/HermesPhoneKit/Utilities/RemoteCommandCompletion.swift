import Foundation

enum RemoteCommandCompletion {
    struct ParsedResult: Equatable {
        let stderr: String
        let exitCode: Int32
    }

    static func makeToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func wrappedCommand(
        environmentExports: String,
        remoteCommand: String,
        standardInputByteCount: Int?,
        token: String
    ) -> String {
        let commandBody: String
        if let standardInputByteCount {
            let inputReader = """
            import pathlib,sys; expected=int(sys.argv[1]); data=sys.stdin.buffer.read(expected); \
            len(data)==expected or (_ for _ in ()).throw(EOFError(f"remote stdin ended with {expected-len(data)} bytes missing")); \
            pathlib.Path(sys.argv[2]).write_bytes(data)
            """
                .replacingOccurrences(of: "\\\n", with: "")
            let quotedReader = inputReader.shellQuotedForTerminalCommand
            commandBody = """
            hermes_stdin_file="$(mktemp "${TMPDIR:-/tmp}/hermes-stdin.XXXXXX")"; \
            if [ -z "$hermes_stdin_file" ]; then \
                hermes_exit_code=1; \
            else \
                trap 'rm -f "$hermes_stdin_file"' EXIT HUP INT TERM; \
                python3 -c \(quotedReader) \(standardInputByteCount) "$hermes_stdin_file"; \
                hermes_input_status=$?; \
                if [ "$hermes_input_status" -eq 0 ]; then \
                    \(remoteCommand) < "$hermes_stdin_file"; \
                    hermes_exit_code=$?; \
                else \
                    hermes_exit_code=$hermes_input_status; \
                fi; \
                rm -f "$hermes_stdin_file"; \
                trap - EXIT HUP INT TERM; \
            fi
            """
        } else {
            commandBody = "\(remoteCommand); hermes_exit_code=$?"
        }

        let marker = markerPrefix(token: token)
        let fullBody = """
        \(environmentExports); \
        \(commandBody); \
        printf '\\n\(marker)%s\\n' "$hermes_exit_code" >&2; \
        exit "$hermes_exit_code"
        """
        return "/bin/sh -lc \(fullBody.shellQuotedForTerminalCommand)"
    }

    static func parse(stderr: String, token: String) -> ParsedResult? {
        let prefix = markerPrefix(token: token)
        var lines = stderr.components(separatedBy: "\n")

        guard let markerIndex = lines.indices.reversed().first(where: { index in
            guard lines[index].hasPrefix(prefix) else { return false }
            return Int32(lines[index].dropFirst(prefix.count)) != nil
        }) else {
            return nil
        }

        guard let exitCode = Int32(lines[markerIndex].dropFirst(prefix.count)) else {
            return nil
        }
        lines.remove(at: markerIndex)

        while lines.first == "" {
            lines.removeFirst()
        }
        while lines.last == "" {
            lines.removeLast()
        }

        return ParsedResult(
            stderr: lines.joined(separator: "\n"),
            exitCode: exitCode
        )
    }

    private static func markerPrefix(token: String) -> String {
        "__HERMES_COMMAND_COMPLETE_\(token)__:"
    }
}
