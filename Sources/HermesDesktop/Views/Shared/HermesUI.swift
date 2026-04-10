import SwiftUI

struct HermesPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let accessory: Accessory

    init(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    init(title: String, subtitle: String) where Accessory == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.accessory = EmptyView()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            accessory
        }
    }
}

struct HermesSurfacePanel<Content: View>: View {
    let title: String?
    let subtitle: String?
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(title)
                            .font(.headline)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

struct HermesInsetSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
    }
}

struct HermesLoadingState: View {
    let label: String
    var minHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

struct HermesLoadingOverlay: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

struct HermesRefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Refreshing…")
                }
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isRefreshing)
    }
}

struct HermesBadge: View {
    let text: String
    let tint: Color
    var isMonospaced = false

    var body: some View {
        Text(text)
            .font(isMonospaced ? .system(.caption, design: .monospaced).weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct HermesLabeledValue: View {
    let label: String
    let value: String
    var isMonospaced = false
    var emphasizeValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(valueFont)
                .foregroundStyle(emphasizeValue ? .primary : .secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var valueFont: Font {
        if isMonospaced {
            return .system(.subheadline, design: .monospaced)
        }

        return emphasizeValue ? .headline : .subheadline
    }
}

struct HermesActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isProminent ? tint : .primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isProminent ? tint.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isProminent ? 0.10 : 0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct HermesExpandableSearchField: View {
    @Binding var text: String

    var prompt = "Search"
    var collapsedWidth: CGFloat = 34
    var expandedWidth: CGFloat = 240

    @FocusState private var isFocused: Bool
    @State private var isExpanded = false

    private var shouldShowExpandedField: Bool {
        isExpanded || !text.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    isExpanded = true
                }
                DispatchQueue.main.async {
                    isFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(shouldShowExpandedField ? .secondary : .primary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt)

            if shouldShowExpandedField {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    text = ""
                    isFocused = false
                    isExpanded = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: shouldShowExpandedField ? expandedWidth : collapsedWidth, height: 30, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(shouldShowExpandedField ? 0.10 : 0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(shouldShowExpandedField ? 0.06 : 0.03), radius: shouldShowExpandedField ? 8 : 4, y: 2)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: shouldShowExpandedField)
        .onAppear {
            isExpanded = !text.isEmpty
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && text.isEmpty {
                isExpanded = false
            }
        }
    }
}
