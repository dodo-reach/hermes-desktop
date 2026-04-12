import Foundation

struct HermesAgentProfile: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let hermesHome: String

    var displayName: String { id.isEmpty ? "Default" : id }
    var isDefault: Bool { id.isEmpty }

    static let defaultProfile = HermesAgentProfile(id: "", hermesHome: "~/.hermes")

    enum CodingKeys: String, CodingKey {
        case id
        case hermesHome
    }
}
