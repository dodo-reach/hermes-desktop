import SwiftUI

struct SwiftTermTerminalView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalMountContainerView {
        let container = TerminalMountContainerView()
        session.mount(in: container, isActive: isActive)
        return container
    }

    func updateNSView(_ nsView: TerminalMountContainerView, context: Context) {
        session.mount(in: nsView, isActive: isActive)
    }

    static func dismantleNSView(_ nsView: TerminalMountContainerView, coordinator: Coordinator) {
        nsView.unmountHostedView()
    }

    final class Coordinator {}
}
