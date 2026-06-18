import Foundation
import Testing

@testable import HermesPhoneKit

struct RemoteJSONResponseDecoderTests {
    @Test
    func decodesCleanJSON() throws {
        let response = try RemoteJSONResponseDecoder.decode(
            ProbeResponse.self,
            stdout: "{\"ok\":true,\"message\":\"ready\"}",
            stderr: ""
        )

        #expect(response.ok)
        #expect(response.message == "ready")
    }

    @Test
    func recoversJSONPayloadSurroundedByRemoteNoise() throws {
        let response = try RemoteJSONResponseDecoder.decode(
            ProbeResponse.self,
            stdout: "Last login: Mon Jun 15\n{\"ok\":true,\"message\":\"ready\"}\nConnection closed",
            stderr: ""
        )

        #expect(response.ok)
        #expect(response.message == "ready")
    }

    @Test
    func preservesDetailedFailureWhenNoPayloadMatches() throws {
        do {
            let _: ProbeResponse = try RemoteJSONResponseDecoder.decode(
                ProbeResponse.self,
                stdout: "Last login: Mon Jun 15\nnot json",
                stderr: "debug line"
            )
            Issue.record("Expected invalid response")
        } catch let error as SSHTransportError {
            guard case .invalidResponse(let message) = error else {
                Issue.record("Expected invalidResponse, got \(error)")
                return
            }
            #expect(message.contains("non-JSON output"))
            #expect(message.contains("Last login"))
        }
    }

    @Test
    func explainsEmptySuccessfulOutputWithoutCallingItMalformedJSON() throws {
        do {
            let _: ProbeResponse = try RemoteJSONResponseDecoder.decode(
                ProbeResponse.self,
                stdout: "",
                stderr: ""
            )
            Issue.record("Expected invalid response")
        } catch let error as SSHTransportError {
            guard case .invalidResponse(let message) = error else {
                Issue.record("Expected invalidResponse, got \(error)")
                return
            }
            #expect(message.contains("without returning its JSON response"))
            #expect(!message.contains("correct format"))
        }
    }
}

private struct ProbeResponse: Decodable {
    let ok: Bool
    let message: String
}
