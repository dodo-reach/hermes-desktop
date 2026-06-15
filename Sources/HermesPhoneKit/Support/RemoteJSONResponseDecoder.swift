import Foundation

enum RemoteJSONResponseDecoder {
    static func decode<Response: Decodable>(
        _ responseType: Response.Type,
        stdout: String,
        stderr: String
    ) throws -> Response {
        guard let data = stdout.data(using: .utf8) else {
            throw SSHTransportError.invalidResponse("Remote output was not valid UTF-8.")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            if let recovered = try recoverSingleJSONPayload(
                responseType,
                from: stdout,
                decoder: decoder
            ) {
                return recovered
            }

            throw SSHTransportError.invalidResponse(
                formattedInvalidJSONResponse(
                    stdout: stdout,
                    stderr: stderr,
                    decodingError: error
                )
            )
        }
    }

    private static func recoverSingleJSONPayload<Response: Decodable>(
        _ responseType: Response.Type,
        from stdout: String,
        decoder: JSONDecoder
    ) throws -> Response? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("{") || trimmed.contains("[") else { return nil }

        var bestMatch: (byteCount: Int, value: Response)?
        for candidate in jsonDocumentCandidates(in: trimmed) {
            guard let data = candidate.data(using: .utf8) else { continue }
            guard let value = try? decoder.decode(responseType, from: data) else { continue }
            let byteCount = data.count
            if bestMatch == nil || byteCount > bestMatch!.byteCount {
                bestMatch = (byteCount, value)
            }
        }
        return bestMatch?.value
    }

    private static func jsonDocumentCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "{" || character == "[" {
                if let endIndex = matchingJSONDocumentEnd(in: text, from: index) {
                    candidates.append(String(text[index ... endIndex]))
                    index = text.index(after: endIndex)
                    continue
                }
            }
            index = text.index(after: index)
        }

        return candidates
    }

    private static func matchingJSONDocumentEnd(in text: String, from startIndex: String.Index) -> String.Index? {
        var stack: [Character] = []
        var index = startIndex
        var isInsideString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                switch character {
                case "\"":
                    isInsideString = true
                case "{":
                    stack.append("}")
                case "[":
                    stack.append("]")
                case "}", "]":
                    guard stack.last == character else { return nil }
                    stack.removeLast()
                    if stack.isEmpty {
                        return index
                    }
                default:
                    break
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func formattedInvalidJSONResponse(
        stdout: String,
        stderr: String,
        decodingError: Error
    ) -> String {
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if looksLikeNonJSONShellOutput(trimmedStdout) {
            let guidance = "Remote command returned non-JSON output. This usually means a shell startup file or Hermes startup command printed text during a non-interactive SSH command. Keep startup files quiet for non-interactive SSH sessions and retry."
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

    private static func decodingErrorDescription(_ error: Error) -> String {
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

    private static func looksLikeNonJSONShellOutput(_ output: String) -> Bool {
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

    private static func shortenedOutputPreview(_ output: String, limit: Int = 240) -> String {
        guard output.count > limit else { return output }
        let endIndex = output.index(output.startIndex, offsetBy: limit)
        return String(output[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
