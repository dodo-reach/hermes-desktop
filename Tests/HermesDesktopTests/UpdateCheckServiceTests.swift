import Foundation
import Testing
@testable import HermesDesktop

struct UpdateCheckServiceTests {
    @Test
    func returnsAvailableUpdateWhenGitHubTagIsNewer() async throws {
        let service = UpdateCheckService.mockingRelease(
            tagName: "v0.6.1",
            htmlURL: "https://github.com/dodo-reach/hermes-desktop/releases/tag/v0.6.1",
            name: "Hermes Desktop v0.6.1",
            body: "Patch release"
        )

        let update = try await service.checkForUpdate(currentVersion: "0.6.0")

        #expect(update?.latestVersion == "0.6.1")
        #expect(update?.currentVersion == "0.6.0")
        #expect(update?.resolvedName == "Hermes Desktop v0.6.1")
        #expect(update?.releaseNotesPreview == "Patch release")
        #expect(update?.htmlURL.absoluteString == "https://github.com/dodo-reach/hermes-desktop/releases/tag/v0.6.1")
    }

    @Test
    func ignoresMatchingVersionWithLeadingTagPrefix() async throws {
        let service = UpdateCheckService.mockingRelease(tagName: "v0.6.1")

        let update = try await service.checkForUpdate(currentVersion: "0.6.1")

        #expect(update == nil)
    }

    @Test
    func comparesNumericVersionComponents() {
        #expect(UpdateCheckService.isVersion("v0.10.0", newerThan: "0.9.9"))
        #expect(!UpdateCheckService.isVersion("v0.6.1", newerThan: "0.6.1"))
        #expect(!UpdateCheckService.isVersion("v0.6.0", newerThan: "0.6.1"))
        #expect(UpdateCheckService.isVersion("v0.6.2+19", newerThan: "0.6.1"))
    }

    @Test
    func ignoresMalformedVersionStrings() {
        #expect(!UpdateCheckService.isVersion("release-2026.07.20", newerThan: "1.2.0"))
        #expect(!UpdateCheckService.isVersion("v1..3", newerThan: "1.2.0"))
        #expect(!UpdateCheckService.isVersion("v1.3.0", newerThan: "current"))
    }

    @Test
    func throwsWhenGitHubReturnsUnexpectedStatus() async throws {
        let service = UpdateCheckService(
            fetch: { _ in
                HTTPResult(statusCode: 500, data: Data())
            }
        )

        await #expect(throws: UpdateCheckError.unexpectedStatusCode(500)) {
            _ = try await service.checkForUpdate(currentVersion: "0.6.0")
        }
    }
}

private extension UpdateCheckService {
    static func mockingRelease(
        tagName: String,
        htmlURL: String = "https://github.com/dodo-reach/hermes-desktop/releases/tag/v0.6.1",
        name: String? = nil,
        body: String? = nil
    ) -> UpdateCheckService {
        let payload: [String: Any?] = [
            "tag_name": tagName,
            "html_url": htmlURL,
            "name": name,
            "body": body
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })

        return UpdateCheckService(
            fetch: { request in
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
                #expect(request.url?.absoluteString == UpdateCheckService.hermesDesktopLatestReleaseURL.absoluteString)
                return HTTPResult(statusCode: 200, data: data)
            }
        )
    }
}
