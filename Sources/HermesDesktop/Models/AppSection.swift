import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case connections
    case overview
    case files
    case sessions
    case workflows
    case cronjobs
    case kanban
    case usage
    case skills
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
        case .workflows:
            "Workflows"
        case .cronjobs:
            "Watchdogs"
        case .kanban:
            "Tasks"
        case .usage:
            "Usage"
        case .skills:
            "Skills"
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
        case .workflows:
            "bookmark.square"
        case .cronjobs:
            "calendar.badge.clock"
        case .kanban:
            "rectangle.3.group"
        case .usage:
            "chart.bar.xaxis"
        case .skills:
            "book.closed"
        case .terminal:
            "terminal"
        }
    }

    var navigationShortcutKey: KeyEquivalent {
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
        }
    }
}
