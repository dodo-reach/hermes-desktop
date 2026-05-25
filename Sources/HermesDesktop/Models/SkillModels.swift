import Foundation

struct SkillListResponse: Codable {
    let ok: Bool
    let items: [SkillSummary]
}

struct SkillDetailResponse: Codable {
    let ok: Bool
    let item: SkillDetail
}

typealias SkillWriteResponse = SkillDetailResponse

struct WorkspaceSkillCatalogResponse: Codable {
    let skills: [WorkspaceSkillItem]
    let total: Int?
    let page: Int?
    let categories: [String]?
    let error: String?
}

struct WorkspaceSkillHubSearchResponse: Codable {
    let ok: Bool?
    let results: [WorkspaceSkillHubItem]
    let source: String?
    let total: Int?
    let warning: String?
    let error: String?
}

struct WorkspaceSkillActionResponse: Codable {
    let ok: Bool?
    let error: String?
    let command: String?
    let message: String?
}

struct WorkspaceSkillSecurity: Codable, Hashable {
    let level: String?
    let flags: [String]?
    let score: Int?
}

struct WorkspaceSkillItem: Codable, Identifiable, Hashable {
    let id: String
    let slug: String?
    let name: String?
    let description: String?
    let author: String?
    let triggers: [String]?
    let tags: [String]?
    let homepage: String?
    let category: String?
    let icon: String?
    let content: String?
    let fileCount: Int?
    let sourcePath: String?
    let installed: Bool?
    let enabled: Bool?
    let builtin: Bool?
    let featuredGroup: String?
    let security: WorkspaceSkillSecurity?
    let origin: String?

    var resolvedName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty { return trimmedName }
        let trimmedSlug = slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSlug.isEmpty { return trimmedSlug }
        return id
    }

    var resolvedSlug: String {
        let trimmedSlug = slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSlug.isEmpty ? id : trimmedSlug
    }

    var resolvedDescription: String? {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var resolvedCategory: String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Uncategorized" : trimmed
    }

    var resolvedOrigin: String {
        let trimmed = origin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "workspace" : trimmed
    }

    var isInstalled: Bool { installed ?? false }
    var isEnabled: Bool { enabled ?? false }
    var isBuiltin: Bool { builtin ?? false }
}

struct WorkspaceSkillHubItem: Codable, Hashable {
    let id: String?
    let name: String?
    let description: String?
    let source: String?
    let identifier: String?
    let trustLevel: String?
    let repo: String?
    let path: String?
    let tags: [String]?
    let installed: Bool?
    let author: String?
    let homepage: String?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case source
        case identifier
        case trustLevel = "trust_level"
        case repo
        case path
        case tags
        case installed
        case author
        case homepage
        case category
    }

    var resolvedIdentifier: String {
        let candidates = [identifier, id, name]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return "skill"
    }

    var resolvedName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? resolvedIdentifier : trimmedName
    }

    var resolvedDescription: String? {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var resolvedSource: String {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "hub" : trimmed
    }

    var isInstalled: Bool { installed ?? false }
}

struct SkillLocator: Codable, Hashable {
    let sourceID: String
    let relativePath: String

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case relativePath = "relative_path"
    }
}

enum SkillSourceKind: String, Codable, Hashable {
    case local
    case external
}

struct SkillSource: Codable, Hashable {
    let id: String
    let kind: SkillSourceKind
    let rootPath: String
    let isReadOnly: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case rootPath = "root_path"
        case isReadOnly = "is_read_only"
    }
}

struct SkillSummary: Codable, Identifiable, Hashable, SkillCatalogItem {
    let id: String
    let locator: SkillLocator
    let source: SkillSource
    let slug: String
    let category: String?
    let relativePath: String
    let name: String?
    let description: String?
    let version: String?
    let platforms: [String]
    let tags: [String]
    let relatedSkills: [String]
    let hasReferences: Bool
    let hasScripts: Bool
    let hasTemplates: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case locator
        case source
        case slug
        case category
        case relativePath = "relative_path"
        case name
        case description
        case version
        case platforms
        case tags
        case relatedSkills = "related_skills"
        case hasReferences = "has_references"
        case hasScripts = "has_scripts"
        case hasTemplates = "has_templates"
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let normalizedQuery = trimmedQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let haystacks = [
            resolvedName,
            resolvedCategory,
            sourceLabel
        ] + platforms + tags + relatedSkills

        return haystacks.contains { value in
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .localizedStandardContains(normalizedQuery)
        }
    }
}

struct SkillDetail: Codable, Identifiable, Hashable, SkillCatalogItem {
    let id: String
    let locator: SkillLocator
    let source: SkillSource
    let slug: String
    let category: String?
    let relativePath: String
    let name: String?
    let description: String?
    let version: String?
    let platforms: [String]
    let tags: [String]
    let relatedSkills: [String]
    let hasReferences: Bool
    let hasScripts: Bool
    let hasTemplates: Bool
    let markdownContent: String
    let contentHash: String

    enum CodingKeys: String, CodingKey {
        case id
        case locator
        case source
        case slug
        case category
        case relativePath = "relative_path"
        case name
        case description
        case version
        case platforms
        case tags
        case relatedSkills = "related_skills"
        case hasReferences = "has_references"
        case hasScripts = "has_scripts"
        case hasTemplates = "has_templates"
        case markdownContent = "markdown_content"
        case contentHash = "content_hash"
    }

}

extension SkillSource {
    var isLocal: Bool {
        kind == .local
    }

    var badgeTitle: String {
        switch kind {
        case .local:
            return "Local"
        case .external:
            return "External"
        }
    }
}

extension SkillSummary {
    var sourceLabel: String {
        source.badgeTitle
    }

    var skillFilePath: String {
        "\(source.rootPath)/\(relativePath)/SKILL.md"
    }
}

enum SkillEditorMode: Identifiable, Equatable {
    case create
    case edit

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit:
            return "edit"
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Skill"
        case .edit:
            return "Edit SKILL.md"
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            return "Create Skill"
        case .edit:
            return "Save Changes"
        }
    }
}

struct SkillDraft: Equatable {
    var name = ""
    var description = ""
    var categoryPath = ""
    var slug = ""
    var version = ""
    var tagsText = ""
    var relatedSkillsText = ""
    var instructions = SkillDraft.defaultInstructions
    var includeReferencesFolder = false
    var includeScriptsFolder = false
    var includeTemplatesFolder = false

    static let defaultInstructions = """
# Overview

Describe when this skill should be used and what it helps Hermes do.

## Workflow

- Step 1
- Step 2
- Step 3

## Notes

Add any guardrails, references, or implementation details that matter.
"""

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedCategoryPath: String? {
        let trimmed = categoryPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedSlug: String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedVersion: String? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedInstructions: String {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var tags: [String] {
        parseCSV(tagsText)
    }

    var relatedSkills: [String] {
        parseCSV(relatedSkillsText)
    }

    var relativePath: String {
        if let normalizedCategoryPath {
            return "\(normalizedCategoryPath)/\(normalizedSlug)"
        }

        return normalizedSlug
    }

    var generatedMarkdown: String {
        var lines = ["---"]
        lines.append("name: \(yamlQuoted(normalizedName))")
        lines.append("description: \(yamlQuoted(normalizedDescription))")

        if let normalizedVersion {
            lines.append("version: \(yamlQuoted(normalizedVersion))")
        }

        if !tags.isEmpty || !relatedSkills.isEmpty {
            lines.append("metadata:")

            if !tags.isEmpty {
                lines.append("  tags:")
                for tag in tags {
                    lines.append("    - \(yamlQuoted(tag))")
                }
            }

            if !relatedSkills.isEmpty {
                lines.append("  related_skills:")
                for skill in relatedSkills {
                    lines.append("    - \(yamlQuoted(skill))")
                }
            }
        }

        lines.append("---")
        lines.append("")
        lines.append(normalizedInstructions)

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    var validationError: String? {
        guard !normalizedName.isEmpty else {
            return "The skill name is required."
        }

        guard !normalizedDescription.isEmpty else {
            return "A short description is required."
        }

        guard !normalizedSlug.isEmpty else {
            return "The skill folder name is required."
        }

        guard isValidPathComponent(normalizedSlug) else {
            return "The skill folder name can only use lowercase letters, numbers, and hyphens."
        }

        if let normalizedCategoryPath {
            let parts = normalizedCategoryPath.split(separator: "/").map(String.init)
            guard parts.allSatisfy(isValidPathComponent) else {
                return "Each category segment must use lowercase letters, numbers, and hyphens."
            }
        }

        guard !normalizedInstructions.isEmpty else {
            return "Add the skill instructions before saving."
        }

        return nil
    }

    mutating func refreshSuggestedSlug() {
        guard normalizedSlug.isEmpty else { return }
        slug = slugified(normalizedName)
    }

    static func from(detail: SkillDetail) -> SkillDraft {
        SkillDraft(
            name: detail.name ?? detail.resolvedName,
            description: detail.description ?? "",
            categoryPath: detail.category ?? "",
            slug: detail.slug,
            version: detail.version ?? "",
            tagsText: detail.tags.joined(separator: ", "),
            relatedSkillsText: detail.relatedSkills.joined(separator: ", "),
            instructions: detail.markdownBodyContent,
            includeReferencesFolder: detail.hasReferences,
            includeScriptsFolder: detail.hasScripts,
            includeTemplatesFolder: detail.hasTemplates
        )
    }

    private func parseCSV(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isValidPathComponent(_ value: String) -> Bool {
        let pattern = #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func slugified(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let replaced = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )

        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

extension SkillDetail {
    var isReadOnly: Bool {
        source.isReadOnly
    }

    var sourceLabel: String {
        source.badgeTitle
    }

    var skillFilePath: String {
        "\(source.rootPath)/\(relativePath)/SKILL.md"
    }

    var markdownBodyContent: String {
        let content = markdownContent
        guard content.hasPrefix("---") else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var closingIndex: Int?
        for index in lines.indices.dropFirst() {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = index
                break
            }
        }

        guard let closingIndex else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let bodyLines = lines.dropFirst(closingIndex + 1)
        return bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SkillFeatureBadge: String, Identifiable {
    case references
    case scripts
    case templates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .references:
            "references"
        case .scripts:
            "scripts"
        case .templates:
            "templates"
        }
    }
}
