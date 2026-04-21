import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case connections
    case overview
    case files
    case sessions
    case cronjobs
    case usage
    case skills
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connections:
            NSLocalizedString("section.connections", comment: "Connections section title")
        case .overview:
            NSLocalizedString("section.overview", comment: "Overview section title")
        case .files:
            NSLocalizedString("section.files", comment: "Files section title")
        case .sessions:
            NSLocalizedString("section.sessions", comment: "Sessions section title")
        case .cronjobs:
            NSLocalizedString("section.cronjobs", comment: "Cron Jobs section title")
        case .usage:
            NSLocalizedString("section.usage", comment: "Usage section title")
        case .skills:
            NSLocalizedString("section.skills", comment: "Skills section title")
        case .terminal:
            NSLocalizedString("section.terminal", comment: "Terminal section title")
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
            "clock.arrow.circlepath"
        case .cronjobs:
            "calendar.badge.clock"
        case .usage:
            "chart.bar.xaxis"
        case .skills:
            "book.closed"
        case .terminal:
            "terminal"
        }
    }
}
