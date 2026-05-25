import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case connections
    case overview
    case files
    case sessions
    case mail
    case contacts
    case calendar
    case workflows
    case cronjobs
    case kanban
    case missionControl
    case operations
    case swarm
    case usage
    case memory
    case skills
    case integrations
    case mcp
    case profiles
    case terminal

    var id: String { rawValue }

    var title: String {
        L10n.string(rawTitle)
    }

    private var rawTitle: String {
        switch self {
        case .connections:
            "Connections"
        case .overview:
            "Homebase"
        case .files:
            "Artifacts"
        case .sessions:
            "Cael Sessions"
        case .mail:
            "Mail"
        case .contacts:
            "Contacts"
        case .calendar:
            "Calendar"
        case .workflows:
            "Workflows"
        case .cronjobs:
            "Watchdogs"
        case .kanban:
            "Tasks"
        case .missionControl:
            "Mission Control"
        case .operations:
            "Ops"
        case .swarm:
            "Swarm"
        case .usage:
            "Usage"
        case .memory:
            "Memory"
        case .skills:
            "Skills"
        case .integrations:
            "Integrations"
        case .mcp:
            "MCP"
        case .profiles:
            "Profiles"
        case .terminal:
            "Terminal"
        }
    }

    var systemImage: String {
        switch self {
        case .connections:
            "network"
        case .overview:
            "waveform.path.ecg"
        case .files:
            "doc.text"
        case .sessions:
            "bubble.left.and.bubble.right"
        case .mail:
            "envelope"
        case .contacts:
            "person.2"
        case .calendar:
            "calendar"
        case .workflows:
            "bookmark.square"
        case .cronjobs:
            "calendar.badge.clock"
        case .kanban:
            "rectangle.3.group"
        case .missionControl:
            "paperplane"
        case .operations:
            "person.2.wave.2"
        case .swarm:
            "person.3.sequence"
        case .usage:
            "chart.bar.xaxis"
        case .memory:
            "brain.head.profile"
        case .skills:
            "book.closed"
        case .integrations:
            "link"
        case .mcp:
            "point.3.connected.trianglepath.dotted"
        case .profiles:
            "person.crop.circle.badge.checkmark"
        case .terminal:
            "terminal"
        }
    }

    var navigationShortcutKey: KeyEquivalent? {
        switch self {
        case .connections:
            return "1"
        case .overview:
            return "2"
        case .sessions:
            return "3"
        case .workflows:
            return "4"
        case .cronjobs:
            return "5"
        case .kanban:
            return "6"
        case .files:
            return "7"
        case .usage:
            return "8"
        case .skills:
            return "9"
        case .terminal:
            return "0"
        case .mail, .contacts, .calendar, .missionControl, .operations, .swarm, .memory, .integrations, .mcp, .profiles:
            return nil
        }
    }

    var isCommandCenterMirrorSection: Bool {
        switch self {
        case .mail, .contacts, .calendar, .missionControl, .operations, .swarm, .memory, .integrations, .mcp, .profiles:
            return true
        case .connections, .overview, .files, .sessions, .workflows, .cronjobs, .kanban, .usage, .skills, .terminal:
            return false
        }
    }
}
