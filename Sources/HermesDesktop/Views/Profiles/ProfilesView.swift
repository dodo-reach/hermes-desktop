import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var appState: AppState

    @State private var profiles: [CaelProfileSummary] = []
    @State private var activeProfileName = "default"
    @State private var selectedProfileName: String?
    @State private var selectedProfileDetail: CaelProfileDetail?
    @State private var isLoading = false
    @State private var isLoadingDetail = false
    @State private var operationProfileName: String?
    @State private var errorMessage: String?
    @State private var isPresentingCreateSheet = false
    @State private var isPresentingRenameSheet = false
    @State private var profilePendingDelete: CaelProfileSummary?
    @State private var createName = ""
    @State private var createCloneFrom = "default"
    @State private var createProvider = ""
    @State private var createModel = ""
    @State private var renameValue = ""
    @State private var descriptionDraft = ""

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Profiles",
                    subtitle: "Native profile management backed by the Cael Workspace /api/profiles contract. The base profile remains `default`; its display agent is Cael."
                ) {
                    HStack(spacing: 10) {
                        Button {
                            Task { await loadProfiles(selectActive: false) }
                        } label: {
                            Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoading || activeConnection == nil)

                        Button {
                            createName = ""
                            createCloneFrom = activeProfileName
                            createProvider = ""
                            createModel = ""
                            isPresentingCreateSheet = true
                        } label: {
                            Label(L10n.string("Create Profile"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(activeConnection == nil)
                    }
                }

                if let errorMessage {
                    HermesInsetSurface {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }

                if activeConnection == nil {
                    ContentUnavailableView(
                        L10n.string("No active host"),
                        systemImage: "network.slash",
                        description: Text(L10n.string("Choose a host before managing Hermes profiles."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        profilesList
                            .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)

                        profileDetail
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .task(id: activeConnection?.commandCenterClientFingerprint) {
            await loadProfiles(selectActive: true)
        }
        .sheet(isPresented: $isPresentingCreateSheet) {
            createProfileSheet
        }
        .sheet(isPresented: $isPresentingRenameSheet) {
            renameProfileSheet
        }
        .alert(
            L10n.string("Delete profile?"),
            isPresented: Binding(
                get: { profilePendingDelete != nil },
                set: { if !$0 { profilePendingDelete = nil } }
            )
        ) {
            Button(L10n.string("Cancel"), role: .cancel) {
                profilePendingDelete = nil
            }
            Button(L10n.string("Delete"), role: .destructive) {
                guard let profile = profilePendingDelete else { return }
                profilePendingDelete = nil
                Task { await deleteProfile(profile) }
            }
        } message: {
            Text(L10n.string("This removes the profile directory from the server-side Hermes profile registry."))
        }
    }

    private var activeConnection: ConnectionProfile? {
        appState.activeConnection
    }

    private var selectedProfile: CaelProfileSummary? {
        guard let selectedProfileName else { return nil }
        return profiles.first { $0.name == selectedProfileName }
    }

    private var profilesList: some View {
        HermesSurfacePanel(
            title: "Server Profiles",
            subtitle: "Source of truth: \(activeConnection?.resolvedCaelWorkspaceBaseURL ?? ConnectionProfile.defaultCaelWorkspaceBaseURL)"
        ) {
            if isLoading && profiles.isEmpty {
                ProgressView(L10n.string("Loading profiles…"))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if profiles.isEmpty {
                ContentUnavailableView(
                    L10n.string("No profiles found"),
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(L10n.string("The Workspace API returned no profile records."))
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                    }
                }
            }
        }
    }

    private func profileRow(_ profile: CaelProfileSummary) -> some View {
        Button {
            selectedProfileName = profile.name
            Task { await loadProfileDetail(profile.name) }
        } label: {
            HermesInsetSurface {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: profile.active ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(profile.active ? Color.accentColor : Color.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(profile.resolvedDisplayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if profile.name == "default" {
                                HermesBadge(text: "base", tint: .secondary)
                            }
                            if profile.active {
                                HermesBadge(text: "active", tint: .accentColor)
                            }
                        }

                        Text(profile.name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let description = profile.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 10) {
                            ProfileMiniStat(label: "skills", value: "\(profile.skillCount)")
                            ProfileMiniStat(label: "sessions", value: "\(profile.sessionCount)")
                            if profile.hasEnv {
                                ProfileMiniStat(label: "env", value: "yes")
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    if selectedProfileName == profile.name {
                        Image(systemName: "chevron.right.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var profileDetail: some View {
        HermesSurfacePanel(
            title: selectedProfile?.resolvedDisplayName ?? "Profile Detail",
            subtitle: selectedProfile.map { "Profile id: \($0.name)" } ?? "Select a server profile to inspect or operate on it."
        ) {
            if isLoadingDetail {
                ProgressView(L10n.string("Loading profile…"))
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else if let profile = selectedProfile {
                VStack(alignment: .leading, spacing: 16) {
                    profileActionBar(profile)
                    profileMetadata(profile)
                    descriptionEditor(profile)
                    if let selectedProfileDetail {
                        detailPaths(selectedProfileDetail)
                    }
                }
            } else {
                ContentUnavailableView(
                    L10n.string("No profile selected"),
                    systemImage: "person.text.rectangle",
                    description: Text(L10n.string("Choose a profile from the server registry."))
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            }
        }
    }

    private func profileActionBar(_ profile: CaelProfileSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                profileButtons(profile)
                Spacer(minLength: 10)
                profileDestructiveButton(profile)
            }
            VStack(alignment: .leading, spacing: 10) {
                profileButtons(profile)
                profileDestructiveButton(profile)
            }
        }
    }

    private func profileButtons(_ profile: CaelProfileSummary) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await activateProfile(profile) }
            } label: {
                Label(L10n.string("Activate"), systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(profile.active || operationProfileName != nil)

            Button {
                renameValue = profile.name == "default" ? "" : profile.name
                isPresentingRenameSheet = true
            } label: {
                Label(L10n.string("Rename"), systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .disabled(profile.name == "default" || operationProfileName != nil)

            Button {
                Task { await loadProfileDetail(profile.name) }
            } label: {
                Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(operationProfileName != nil)
        }
    }

    private func profileDestructiveButton(_ profile: CaelProfileSummary) -> some View {
        Button(role: .destructive) {
            profilePendingDelete = profile
        } label: {
            Label(L10n.string("Delete"), systemImage: "trash")
        }
        .buttonStyle(.borderless)
        .disabled(profile.name == "default" || profile.active || operationProfileName != nil)
    }

    private func profileMetadata(_ profile: CaelProfileSummary) -> some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        profileValue(label: "Display", value: profile.resolvedDisplayName)
                        profileValue(label: "Base Profile", value: profile.name)
                        profileValue(label: "Provider", value: profile.provider ?? "Not set")
                        profileValue(label: "Model", value: profile.model ?? "Not set")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        profileValue(label: "Display", value: profile.resolvedDisplayName)
                        profileValue(label: "Base Profile", value: profile.name)
                        profileValue(label: "Provider", value: profile.provider ?? "Not set")
                        profileValue(label: "Model", value: profile.model ?? "Not set")
                    }
                }

                Text(profile.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }

    private func descriptionEditor(_ profile: CaelProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Description"))
                .font(.headline)
            TextEditor(text: $descriptionDraft)
                .font(.body)
                .frame(minHeight: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            HStack {
                Button {
                    Task { await saveDescription(profile) }
                } label: {
                    Label(L10n.string("Save Description"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(operationProfileName != nil)

                Spacer()
            }
        }
    }

    private func detailPaths(_ detail: CaelProfileDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Server Paths"))
                .font(.headline)
            profileValue(label: "Hermes home", value: detail.path)
            profileValue(label: "Sessions", value: detail.sessionsDir ?? "Not available")
            profileValue(label: "Skills", value: detail.skillsDir ?? "Not available")
            profileValue(label: "Env linked", value: detail.hasEnv ? "yes" : "no")
        }
    }

    private func profileValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: label == "Display" ? .default : .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private var createProfileSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("Create Profile"))
                .font(.title2.weight(.semibold))
            profileTextField("Name", text: $createName, prompt: "builder")
            profileTextField("Clone from", text: $createCloneFrom, prompt: "default")
            profileTextField("Provider", text: $createProvider, prompt: "optional")
            profileTextField("Model", text: $createModel, prompt: "optional")
            HStack {
                Spacer()
                Button(L10n.string("Cancel")) {
                    isPresentingCreateSheet = false
                }
                Button(L10n.string("Create")) {
                    Task { await createProfile() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isCreateNameValid || operationProfileName != nil)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var renameProfileSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("Rename Profile"))
                .font(.title2.weight(.semibold))
            profileTextField("New name", text: $renameValue, prompt: "researcher")
            HStack {
                Spacer()
                Button(L10n.string("Cancel")) {
                    isPresentingRenameSheet = false
                }
                Button(L10n.string("Rename")) {
                    Task { await renameProfile() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isRenameNameValid || operationProfileName != nil)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func profileTextField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var isCreateNameValid: Bool {
        isProfileNameValid(createName) && createName.trimmingCharacters(in: .whitespacesAndNewlines) != "default"
    }

    private var isRenameNameValid: Bool {
        isProfileNameValid(renameValue) && renameValue.trimmingCharacters(in: .whitespacesAndNewlines) != "default"
    }

    private func isProfileNameValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return false }
        return trimmed.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private func loadProfiles(selectActive: Bool) async {
        guard let connection = activeConnection else {
            profiles = []
            selectedProfileName = nil
            selectedProfileDetail = nil
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let response = try await appState.caelWorkspaceAPIService.loadProfiles(connection: connection)
            profiles = response.profiles
            activeProfileName = response.activeProfile
            if selectActive || selectedProfileName == nil || profiles.contains(where: { $0.name == selectedProfileName }) == false {
                selectedProfileName = response.activeProfile
            }
            if let selectedProfileName {
                await loadProfileDetail(selectedProfileName)
            }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func loadProfileDetail(_ name: String) async {
        guard let connection = activeConnection else { return }
        isLoadingDetail = true
        errorMessage = nil
        do {
            let detail = try await appState.caelWorkspaceAPIService.readProfile(connection: connection, name: name)
            guard selectedProfileName == name else { return }
            selectedProfileDetail = detail
            descriptionDraft = detail.description
            isLoadingDetail = false
        } catch {
            isLoadingDetail = false
            errorMessage = error.localizedDescription
        }
    }

    private func createProfile() async {
        guard let connection = activeConnection else { return }
        let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
        operationProfileName = "__create__"
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.createProfile(
                connection: connection,
                name: name,
                cloneFrom: createCloneFrom,
                provider: createProvider,
                model: createModel
            )
            isPresentingCreateSheet = false
            selectedProfileName = name
            operationProfileName = nil
            await loadProfiles(selectActive: false)
        } catch {
            operationProfileName = nil
            errorMessage = error.localizedDescription
        }
    }

    private func activateProfile(_ profile: CaelProfileSummary) async {
        guard let connection = activeConnection else { return }
        operationProfileName = profile.name
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.activateProfile(connection: connection, name: profile.name)
            operationProfileName = nil
            await appState.switchHermesProfile(to: profile.name)
            await loadProfiles(selectActive: true)
        } catch {
            operationProfileName = nil
            errorMessage = error.localizedDescription
        }
    }

    private func renameProfile() async {
        guard let connection = activeConnection,
              let selectedProfile,
              selectedProfile.name != "default" else {
            return
        }
        let newName = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        operationProfileName = selectedProfile.name
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.renameProfile(connection: connection, oldName: selectedProfile.name, newName: newName)
            isPresentingRenameSheet = false
            selectedProfileName = newName
            operationProfileName = nil
            await loadProfiles(selectActive: false)
        } catch {
            operationProfileName = nil
            errorMessage = error.localizedDescription
        }
    }

    private func saveDescription(_ profile: CaelProfileSummary) async {
        guard let connection = activeConnection else { return }
        operationProfileName = profile.name
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.updateProfileDescription(
                connection: connection,
                name: profile.name,
                description: descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            operationProfileName = nil
            await loadProfiles(selectActive: false)
        } catch {
            operationProfileName = nil
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProfile(_ profile: CaelProfileSummary) async {
        guard let connection = activeConnection else { return }
        operationProfileName = profile.name
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.deleteProfile(connection: connection, name: profile.name)
            if selectedProfileName == profile.name {
                selectedProfileName = activeProfileName
                selectedProfileDetail = nil
            }
            operationProfileName = nil
            await loadProfiles(selectActive: false)
        } catch {
            operationProfileName = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileMiniStat: View {
    let label: String
    let value: String

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
