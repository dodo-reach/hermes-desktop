import SwiftUI

struct SwiftTermTerminalView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    let appearance: TerminalThemeAppearance
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalMountContainerView {
        let container = TerminalMountContainerView()
        session.mount(in: container, appearance: appearance, isActive: isActive)
        return container
    }

    func updateNSView(_ nsView: TerminalMountContainerView, context: Context) {
        session.mount(in: nsView, appearance: appearance, isActive: isActive)
    }

    static func dismantleNSView(_ nsView: TerminalMountContainerView, coordinator: Coordinator) {
        nsView.unmountHostedView()
    }

    final class Coordinator {}
}
