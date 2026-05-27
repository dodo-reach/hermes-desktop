import Foundation

struct ToolArtifactSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sessionId: String
    let messageId: String?
    let toolCallId: String?
    let toolName: String?
    let kind: String
    let title: String
    let summary: String
    let preview: String
    let contentSize: Int
    let contentPath: String
    let createdAt: Double

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }
}

struct ToolArtifactDetail: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sessionId: String
    let messageId: String?
    let toolCallId: String?
    let toolName: String?
    let kind: String
    let title: String
    let summary: String
    let preview: String
    let contentSize: Int
    let contentPath: String
    let createdAt: Double
    let content: String

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }
}
