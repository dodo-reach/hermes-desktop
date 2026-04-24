import SwiftUI

struct ConnectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case label
        case alias
        case host
        case user
        case port
        case hermesProfile
    }

    @State private var draft: ConnectionProfile
    @State private var portText: String
    @FocusState private var focusedField: Field?
    let isEditing: Bool
    let onSave: (ConnectionProfile) -> Void

    init(connection: ConnectionProfile, isEditing: Bool, onSave: @escaping (ConnectionProfile) -> Void) {
        _draft = State(initialValue: connection)
        _portText = State(initialValue: connection.sshPort.map(String.init) ?? "")
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HermesPageHeader(
                        title: isEditing ? "Edit Host" : "New Host",
                        subtitle: "Set the SSH details Hermes Desktop should use for discovery, file editing, sessions and terminal access."
                    )

                    HermesSurfacePanel(
                        title: "Connection Details",
                        subtitle: "Give the host a clear name, then prefer an SSH alias whenever you have one."
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            EditorField(label: "Name") {
                                TextField("Home Pi, Studio Mac, Prod VPS", text: $draft.label)
                                    .focused($focusedField, equals: .label)
                                    .textFieldStyle(.roundedBorder)
                            }

                            EditorField(label: "SSH alias") {
                                TextField("hermes-home", text: $draft.sshAlias)
                                    .focused($focusedField, equals: .alias)
                                    .textFieldStyle(.roundedBorder)
                            }

                            EditorField(label: "Host or IP address") {
                                TextField("mac-studio.local, 203.0.113.10, localhost", text: $draft.sshHost)
                                    .focused($focusedField, equals: .host)
                                    .textFieldStyle(.roundedBorder)
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 14) {
                                    EditorField(label: "SSH user") {
                                        TextField("alex", text: $draft.sshUser)
                                            .focused($focusedField, equals: .user)
                                            .textFieldStyle(.roundedBorder)
                                    }

                                    EditorField(label: "SSH port") {
                                        TextField("22", text: $portText)
                                            .focused($focusedField, equals: .port)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 14) {
                                    EditorField(label: "SSH user") {
                                        TextField("alex", text: $draft.sshUser)
                                            .focused($focusedField, equals: .user)
                                            .textFieldStyle(.roundedBorder)
                                    }

                                    EditorField(label: "SSH port") {
                                        TextField("22", text: $portText)
                                            .focused($focusedField, equals: .port)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                            }

                            EditorField(label: "Hermes profile") {
                                TextField("default or researcher", text: hermesProfileBinding)
                                    .focused($focusedField, equals: .hermesProfile)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    HermesSurfacePanel(
                        title: "How Hermes Connects",
                        subtitle: "The goal is to keep the profile understandable without hiding the technical model."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ConnectionHintRow(
                                title: "Preferred setup",
                                detail: "Use an SSH alias when possible. It keeps the system SSH config as the source of truth."
                            )

                            ConnectionHintRow(
                                title: "Same Mac",
                                detail: "If Hermes runs on this Mac, stay with the SSH model and use localhost, the local hostname, or a local SSH alias."
                            )

                            ConnectionHintRow(
                                title: "Authentication",
                                detail: "SSH must already work from this Mac without interactive prompts. Password login may still exist on the host, but Hermes Desktop expects keys, an SSH agent, or another non-interactive SSH path for the actual connection it uses."
                            )

                            ConnectionHintRow(
                                title: "Network path",
                                detail: "The Mac and Hermes host do not need to be on the same Wi-Fi. Local network, public IP, VPN, or Tailscale all work as long as standard ssh from this Mac reaches the host."
                            )

                            if draft.trimmedAlias != nil && draft.trimmedHost != nil {
                                HermesInsetSurface {
                                    Text("The SSH alias currently takes priority over Host. The Host value is preserved in the profile, but it will be ignored while the alias is present.")
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                            ConnectionHintRow(
                                title: "Overrides",
                                detail: "SSH user and port are optional. Leave them empty to keep the remote defaults."
                            )
                        }

                        HermesInsetSurface {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Hermes profile")
                                    .font(.headline)

                                Text("Leave it empty for the default Hermes home at `~/.hermes`. Set a profile name like `researcher` to target `~/.hermes/profiles/researcher` on the same host.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    }

                    HermesSurfacePanel(
                        title: "Examples",
                        subtitle: "A few common patterns that work well with Hermes Desktop."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ExampleValueRow(label: "Raspberry Pi", value: "Alias `hermes-home` or host `raspberrypi.local`")
                            ExampleValueRow(label: "Remote Mac", value: "Host `mac-studio.local`")
                            ExampleValueRow(label: "VPS", value: "Host `vps.example.com` or `203.0.113.10`")
                            ExampleValueRow(label: "Same Mac", value: "Host `localhost` or a local SSH alias")
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updatedDraft = draft
                        updatedDraft.sshPort = parsedPort
                        onSave(updatedDraft)
                        dismiss()
                    }
                    .disabled(!isDraftValid)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                focusedField = .label
            }
        }
    }

    private var parsedPort: Int? {
        let trimmed = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private var isDraftValid: Bool {
        let hasValidPort = portText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedPort != nil
        var candidate = draft
        candidate.sshPort = parsedPort
        return hasValidPort && candidate.isValid
    }

    private var hermesProfileBinding: Binding<String> {
        Binding {
            draft.hermesProfile ?? ""
        } set: { newValue in
            draft.hermesProfile = newValue
        }
    }
}

private struct EditorField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(.caption)
                .foregroundStyle(.secondary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionHintRow: View {
    let title: String
    let detail: String

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(title))
                    .font(.headline)

                Text(L10n.string(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ExampleValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(label))
                    .font(.headline)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
