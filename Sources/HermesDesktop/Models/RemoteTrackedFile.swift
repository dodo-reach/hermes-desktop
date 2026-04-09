import Foundation

enum RemoteTrackedFile: String, CaseIterable, Identifiable {
    case user
    case memory
    case soul

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user:
            "USER.md"
        case .memory:
            "MEMORY.md"
        case .soul:
            "SOUL.md"
        }
    }

    var fileName: String { title }

    var remoteTildePath: String {
        switch self {
        case .user:
            "~/.hermes/memories/USER.md"
        case .memory:
            "~/.hermes/memories/MEMORY.md"
        case .soul:
            "~/.hermes/SOUL.md"
        }
    }
}
