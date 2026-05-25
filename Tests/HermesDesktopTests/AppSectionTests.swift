import Testing

@testable import HermesDesktop

struct AppSectionTests {
    @Test
    func navigationShortcutsStayStableAcrossAllSections() {
        #expect(AppSection.connections.navigationShortcutKey == "1")
        #expect(AppSection.overview.navigationShortcutKey == "2")
        #expect(AppSection.sessions.navigationShortcutKey == "3")
        #expect(AppSection.workflows.navigationShortcutKey == "4")
        #expect(AppSection.cronjobs.navigationShortcutKey == "5")
        #expect(AppSection.kanban.navigationShortcutKey == "6")
        #expect(AppSection.files.navigationShortcutKey == "7")
        #expect(AppSection.usage.navigationShortcutKey == "8")
        #expect(AppSection.skills.navigationShortcutKey == "9")
        #expect(AppSection.terminal.navigationShortcutKey == "0")
    }

    @Test
    func commandCenterMirrorSectionsDoNotClaimNumberShortcuts() {
        let mirrorSections: [AppSection] = [
            .mail,
            .contacts,
            .calendar,
            .missionControl,
            .operations,
            .swarm,
            .memory,
            .integrations,
            .mcp,
            .profiles
        ]

        for section in mirrorSections {
            #expect(section.isCommandCenterMirrorSection)
            #expect(section.navigationShortcutKey == nil)
        }
    }
}
