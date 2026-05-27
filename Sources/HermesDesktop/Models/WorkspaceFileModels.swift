import Foundation

enum WorkspaceFileLimits {
    static let maxEditableFileBytes: Int64 = 10 * 1_000_000
    static let maxDesktopUploadBytes: Int = 10 * 1024 * 1024

    static func decimalMegabytes(for byteCount: Int64) -> String {
        String(format: "%.1f MB", Double(byteCount) / 1_000_000)
    }
}

struct WorkspaceFileUploadResult: Codable, Hashable, Sendable {
    let ok: Bool
    let path: String?
    let size: Int?
    let contentHash: String?
    let error: String?
}

struct WorkspacePreviewFile: Codable, Hashable, Sendable {
    let ok: Bool?
    let path: String
    let mime: String
    let kind: String
    let size: Int64
    let contentHash: String?
    let content: String?
    let contentBase64: String?

    var isText: Bool { kind == "text" }
    var isImage: Bool { kind == "image" }
}

struct WorkspaceFileBookmark: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var workspaceScopeFingerprint: String
    var remotePath: String
    var title: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        workspaceScopeFingerprint: String,
        remotePath: String,
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceScopeFingerprint = workspaceScopeFingerprint
        self.remotePath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var fileID: String {
        "bookmark:\(id.uuidString)"
    }

    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        return Self.displayTitle(for: remotePath)
    }

    static func displayTitle(for remotePath: String) -> String {
        let trimmed = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled file" }

        let withoutTrailingSlash = trimmed.hasSuffix("/") && trimmed.count > 1
            ? String(trimmed.dropLast())
            : trimmed
        return withoutTrailingSlash.split(separator: "/").last.map(String.init) ?? withoutTrailingSlash
    }
}

struct WorkspaceFileReference: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case canonical(RemoteTrackedFile)
        case bookmark(UUID)
    }

    let id: String
    let title: String
    let subtitle: String
    let remotePath: String
    let kind: Kind
    let systemImage: String

    var bookmarkID: UUID? {
        guard case .bookmark(let id) = kind else { return nil }
        return id
    }

    var isRemovable: Bool {
        bookmarkID != nil
    }

    static func canonical(_ trackedFile: RemoteTrackedFile, remotePath: String) -> WorkspaceFileReference {
        WorkspaceFileReference(
            id: trackedFile.workspaceFileID,
            title: trackedFile.title,
            subtitle: remotePath,
            remotePath: remotePath,
            kind: .canonical(trackedFile),
            systemImage: "doc.text"
        )
    }

    static func bookmark(_ bookmark: WorkspaceFileBookmark) -> WorkspaceFileReference {
        WorkspaceFileReference(
            id: bookmark.fileID,
            title: bookmark.displayTitle,
            subtitle: bookmark.remotePath,
            remotePath: bookmark.remotePath,
            kind: .bookmark(bookmark.id),
            systemImage: "bookmark.fill"
        )
    }
}

struct WorkspaceFileBookmarkGroup: Identifiable, Hashable, Sendable {
    let directoryPath: String
    let title: String
    let references: [WorkspaceFileReference]

    var id: String {
        directoryPath
    }

    static func groups(for references: [WorkspaceFileReference]) -> [WorkspaceFileBookmarkGroup] {
        let bookmarks = references.filter { $0.bookmarkID != nil }
        let groupedReferences = Dictionary(grouping: bookmarks) { reference in
            parentDirectoryPath(for: reference.remotePath)
        }

        return groupedReferences
            .map { directoryPath, references in
                WorkspaceFileBookmarkGroup(
                    directoryPath: directoryPath,
                    title: displayTitle(forDirectoryPath: directoryPath),
                    references: references.sorted(by: compareReferences)
                )
            }
            .sorted(by: compareGroups)
    }

    static func parentDirectoryPath(for remotePath: String) -> String {
        let trimmed = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmingTrailingSlashes(from: trimmed)
        guard !normalized.isEmpty else { return "." }
        guard normalized != "/" else { return "/" }
        guard let slashIndex = normalized.lastIndex(of: "/") else { return "." }
        guard slashIndex != normalized.startIndex else { return "/" }

        return String(normalized[..<slashIndex])
    }

    static func displayTitle(forDirectoryPath directoryPath: String) -> String {
        let trimmed = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmingTrailingSlashes(from: trimmed)
        guard !normalized.isEmpty else { return "." }
        guard normalized != "/" else { return "/" }

        return normalized.split(separator: "/").last.map(String.init) ?? normalized
    }

    private static func compareGroups(
        _ lhs: WorkspaceFileBookmarkGroup,
        _ rhs: WorkspaceFileBookmarkGroup
    ) -> Bool {
        let pathComparison = lhs.directoryPath.localizedCaseInsensitiveCompare(rhs.directoryPath)
        if pathComparison != .orderedSame {
            return pathComparison == .orderedAscending
        }

        return lhs.directoryPath < rhs.directoryPath
    }

    private static func compareReferences(
        _ lhs: WorkspaceFileReference,
        _ rhs: WorkspaceFileReference
    ) -> Bool {
        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        let pathComparison = lhs.remotePath.localizedCaseInsensitiveCompare(rhs.remotePath)
        if pathComparison != .orderedSame {
            return pathComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private static func trimmingTrailingSlashes(from path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

struct RemoteDirectoryListing: Decodable, Sendable {
    let requestedPath: String
    let resolvedPath: String
    let displayPath: String
    let parentPath: String?
    let parentDisplayPath: String?
    let entries: [RemoteDirectoryEntry]
    let totalEntryCount: Int
    let isTruncated: Bool

    enum CodingKeys: String, CodingKey {
        case requestedPath = "requested_path"
        case resolvedPath = "resolved_path"
        case displayPath = "display_path"
        case parentPath = "parent_path"
        case parentDisplayPath = "parent_display_path"
        case entries
        case totalEntryCount = "total_entry_count"
        case isTruncated = "is_truncated"
    }
}

struct RemoteDirectoryEntry: Decodable, Identifiable, Hashable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case directory
        case file
        case symlink
        case other
    }

    let name: String
    let path: String
    let displayPath: String
    let kind: Kind
    let size: Int64?
    let modifiedAt: Double?
    let isReadable: Bool
    let isWritable: Bool
    let isSymlink: Bool

    var id: String { path }

    var modifiedDate: Date? {
        modifiedAt.map { Date(timeIntervalSince1970: $0) }
    }

    var canOpenDirectory: Bool {
        kind == .directory && isReadable
    }

    var canBookmark: Bool {
        kind == .file && isReadable && !isTooLargeToEdit
    }

    var isTooLargeToEdit: Bool {
        guard kind == .file, let size else { return false }
        return size > WorkspaceFileLimits.maxEditableFileBytes
    }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case displayPath = "display_path"
        case kind
        case size
        case modifiedAt = "modified_at"
        case isReadable = "is_readable"
        case isWritable = "is_writable"
        case isSymlink = "is_symlink"
    }
}

extension RemoteTrackedFile {
    var workspaceFileID: String {
        "canonical:\(rawValue)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
