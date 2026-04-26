import Foundation

enum RemoteTrackedFile: String, CaseIterable, Identifiable {
    case user
    case memory
    case soul
    case agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user:
            "USER.md"
        case .memory:
            "MEMORY.md"
        case .soul:
            "SOUL.md"
        case .agents:
            "AGENTS.md"
        }
    }

    var fileName: String { title }

    var relativePathFromHermesHome: String {
        switch self {
        case .user:
            "memories/USER.md"
        case .memory:
            "memories/MEMORY.md"
        case .soul:
            "SOUL.md"
        case .agents:
            "AGENTS.md"
        }
    }

    func resolvedRemotePath(using paths: RemoteHermesPaths?) -> String? {
        guard let paths else { return nil }

        switch self {
        case .user:
            return paths.user
        case .memory:
            return paths.memory
        case .soul:
            return paths.soul
        case .agents:
            return nil
        }
    }
}
