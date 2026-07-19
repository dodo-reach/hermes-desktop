import Foundation

struct UpdateCheckService: Sendable {
    static let hermesDesktopLatestReleaseURL = URL(
        string: "https://api.github.com/repos/dodo-reach/hermes-desktop/releases/latest"
    )!

    private let latestReleaseURL: URL
    private let currentVersionProvider: @Sendable () -> String
    private let fetch: @Sendable (URLRequest) async throws -> HTTPResult

    init(
        latestReleaseURL: URL = Self.hermesDesktopLatestReleaseURL,
        currentVersionProvider: @escaping @Sendable () -> String = { Self.bundleShortVersion() },
        fetch: @escaping @Sendable (URLRequest) async throws -> HTTPResult = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            return HTTPResult(statusCode: statusCode, data: data)
        }
    ) {
        self.latestReleaseURL = latestReleaseURL
        self.currentVersionProvider = currentVersionProvider
        self.fetch = fetch
    }

    func checkForUpdate() async throws -> AvailableUpdate? {
        try await checkForUpdate(currentVersion: currentVersionProvider())
    }

    func checkForUpdate(currentVersion: String) async throws -> AvailableUpdate? {
        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("HermesDesktop", forHTTPHeaderField: "User-Agent")

        let result = try await fetch(request)
        guard result.statusCode == 200 else {
            throw UpdateCheckError.unexpectedStatusCode(result.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: result.data)
        guard Self.isVersion(release.tagName, newerThan: currentVersion) else {
            return nil
        }

        return AvailableUpdate(
            currentVersion: Self.normalizedDisplayVersion(currentVersion),
            tagName: release.tagName,
            htmlURL: release.htmlURL,
            name: release.name,
            body: release.body
        )
    }

    static func bundleShortVersion(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return normalizedDisplayVersion(version ?? "0.0.0")
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        guard
            let candidateComponents = numericVersionComponents(from: candidate),
            let currentComponents = numericVersionComponents(from: current)
        else {
            return false
        }
        let componentCount = max(candidateComponents.count, currentComponents.count)

        for index in 0..<componentCount {
            let candidateValue = index < candidateComponents.count ? candidateComponents[index] : 0
            let currentValue = index < currentComponents.count ? currentComponents[index] : 0

            if candidateValue > currentValue {
                return true
            }
            if candidateValue < currentValue {
                return false
            }
        }

        return false
    }

    private static func normalizedDisplayVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "v" || first == "V" else {
            return trimmed
        }

        return String(trimmed.dropFirst())
    }

    private static func numericVersionComponents(from value: String) -> [Int]? {
        let version = normalizedDisplayVersion(value)
        let coreVersion = version.split(
            whereSeparator: { $0 == "-" || $0 == "+" }
        ).first ?? ""
        let components = coreVersion.split(
            separator: ".",
            omittingEmptySubsequences: false
        )

        guard !components.isEmpty else {
            return nil
        }

        var numbers: [Int] = []
        for component in components {
            guard
                !component.isEmpty,
                component.allSatisfy(\.isNumber),
                let number = Int(component)
            else {
                return nil
            }
            numbers.append(number)
        }

        return numbers
    }
}

struct AvailableUpdate: Identifiable, Equatable, Sendable {
    var id: String {
        tagName
    }

    let currentVersion: String
    let tagName: String
    let htmlURL: URL
    let name: String?
    let body: String?

    var latestVersion: String {
        if tagName.first == "v" || tagName.first == "V" {
            return String(tagName.dropFirst())
        }

        return tagName
    }

    var resolvedName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? tagName : trimmedName
    }

    var releaseNotesPreview: String? {
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedBody.isEmpty else { return nil }

        if trimmedBody.count <= 700 {
            return trimmedBody
        }

        let endIndex = trimmedBody.index(trimmedBody.startIndex, offsetBy: 700)
        return String(trimmedBody[..<endIndex]) + "..."
    }
}

struct HTTPResult: Sendable {
    let statusCode: Int
    let data: Data
}

enum UpdateCheckError: LocalizedError, Equatable {
    case unexpectedStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatusCode(let statusCode):
            return L10n.string(
                "GitHub returned HTTP %@ while checking the latest Hermes Desktop release.",
                "\(statusCode)"
            )
        }
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let htmlURL: URL
    let name: String?
    let body: String?

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
        case body
    }
}
