import Foundation

struct RemoteDiscovery: Codable {
    let ok: Bool
    let remoteHome: String
    let hermesHome: String
    let activeProfile: RemoteHermesProfile
    let availableProfiles: [RemoteHermesProfile]
    let paths: RemoteHermesPaths
    let exists: RemoteHermesPathExistence
    let sessionStore: RemoteSessionStore?

    enum CodingKeys: String, CodingKey {
        case ok
        case remoteHome = "remote_home"
        case hermesHome = "hermes_home"
        case activeProfile = "active_profile"
        case availableProfiles = "available_profiles"
        case paths
        case exists
        case sessionStore = "session_store"
    }
}

struct RemoteHermesProfile: Codable, Identifiable {
    let name: String
    let path: String
    let isDefault: Bool
    let exists: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case isDefault = "is_default"
        case exists
    }
}

struct RemoteHermesPaths: Codable {
    let user: String
    let memory: String
    let soul: String
    let sessionsDir: String
    let cronJobs: String

    enum CodingKeys: String, CodingKey {
        case user
        case memory
        case soul
        case sessionsDir = "sessions_dir"
        case cronJobs = "cron_jobs"
    }
}

struct RemoteHermesPathExistence: Codable {
    let user: Bool
    let memory: Bool
    let soul: Bool
    let sessionsDir: Bool
    let cronJobs: Bool

    enum CodingKeys: String, CodingKey {
        case user
        case memory
        case soul
        case sessionsDir = "sessions_dir"
        case cronJobs = "cron_jobs"
    }
}

struct RemoteSessionStore: Codable {
    let kind: String
    let path: String
    let sessionTable: String?
    let messageTable: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case sessionTable = "session_table"
        case messageTable = "message_table"
    }
}
