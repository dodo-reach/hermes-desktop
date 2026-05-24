import AppKit
import SwiftUI

@main
struct HermesDesktopApp: App {
    @NSApplicationDelegateAdaptor(HermesApplicationDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Cael Desktop") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 940, minHeight: 520)
                .tint(HermesTheme.accent)
                .preferredColorScheme(.dark)
                .background(HermesTheme.background)
                .background(HermesWindowTitleBarConfigurator())
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            HermesDesktopCommands(appState: appState)
        }
    }
}
