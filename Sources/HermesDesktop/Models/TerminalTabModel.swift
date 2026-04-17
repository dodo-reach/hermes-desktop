import Foundation

final class TerminalTabModel: ObservableObject, Identifiable {
    let id = UUID()
    let connectionID: UUID
    let hostConnectionFingerprint: String
    let workspaceScopeFingerprint: String
    let session: TerminalSession
    @Published var title: String

    init(
        title: String,
        connectionID: UUID,
        hostConnectionFingerprint: String,
        workspaceScopeFingerprint: String,
        session: TerminalSession
    ) {
        self.title = title
        self.connectionID = connectionID
        self.hostConnectionFingerprint = hostConnectionFingerprint
        self.workspaceScopeFingerprint = workspaceScopeFingerprint
        self.session = session
    }
}
