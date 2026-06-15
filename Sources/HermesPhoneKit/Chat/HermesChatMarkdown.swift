import Foundation
import SwiftUI

struct HermesMarkdownTable: Equatable, Sendable {
    var headers: [String]
    var rows: [[String]]
}

enum HermesMarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case unorderedList([String])
    case orderedList([String])
    case blockquote(String)
    case codeBlock(language: String?, code: String)
    case table(HermesMarkdownTable)
}

enum HermesChatMarkdownParser {
    static func parse(_ markdown: String) -> [HermesMarkdownBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [HermesMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let codeBlock = parseCodeBlock(lines: lines, startIndex: index) {
                blocks.append(.codeBlock(language: codeBlock.language, code: codeBlock.code))
                index = codeBlock.nextIndex
                continue
            }

            if let table = parseTable(lines: lines, startIndex: index) {
                blocks.append(.table(table.table))
                index = table.nextIndex
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isBlockquoteLine(trimmed) {
                let parsed = parseBlockquote(lines: lines, startIndex: index)
                blocks.append(.blockquote(parsed.text))
                index = parsed.nextIndex
                continue
            }

            if unorderedListItem(trimmed) != nil {
                let parsed = parseUnorderedList(lines: lines, startIndex: index)
                blocks.append(.unorderedList(parsed.items))
                index = parsed.nextIndex
                continue
            }

            if orderedListItem(trimmed) != nil {
                let parsed = parseOrderedList(lines: lines, startIndex: index)
                blocks.append(.orderedList(parsed.items))
                index = parsed.nextIndex
                continue
            }

            let parsed = parseParagraph(lines: lines, startIndex: index)
            blocks.append(.paragraph(parsed.text))
            index = parsed.nextIndex
        }

        return blocks
    }

    private static func parseCodeBlock(
        lines: [String],
        startIndex: Int
    ) -> (language: String?, code: String, nextIndex: Int)? {
        let trimmed = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let fence: String
        if trimmed.hasPrefix("```") {
            fence = "```"
        } else if trimmed.hasPrefix("~~~") {
            fence = "~~~"
        } else {
            return nil
        }

        let language = trimmed.dropFirst(fence.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var codeLines: [String] = []
        var index = startIndex + 1
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                return (
                    language.isEmpty ? nil : language,
                    codeLines.joined(separator: "\n"),
                    index + 1
                )
            }
            codeLines.append(line)
            index += 1
        }

        return (
            language.isEmpty ? nil : language,
            codeLines.joined(separator: "\n"),
            index
        )
    }

    private static func parseTable(
        lines: [String],
        startIndex: Int
    ) -> (table: HermesMarkdownTable, nextIndex: Int)? {
        guard startIndex + 1 < lines.count,
              isTableRow(lines[startIndex]),
              isTableSeparator(lines[startIndex + 1]) else {
            return nil
        }

        let headers = splitTableRow(lines[startIndex])
        guard !headers.isEmpty else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            let line = lines[index]
            guard isTableRow(line), !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                break
            }
            rows.append(splitTableRow(line))
            index += 1
        }

        return (HermesMarkdownTable(headers: headers, rows: rows), index)
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && !trimmed.hasPrefix("```")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var count = 0
        for character in trimmed {
            if character == "#" {
                count += 1
            } else {
                break
            }
        }
        guard (1 ... 4).contains(count),
              trimmed.dropFirst(count).first == " " else { return nil }
        let text = trimmed.dropFirst(count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (count, text)
    }

    private static func isBlockquoteLine(_ trimmed: String) -> Bool {
        trimmed.hasPrefix(">")
    }

    private static func parseBlockquote(
        lines: [String],
        startIndex: Int
    ) -> (text: String, nextIndex: Int) {
        var quoteLines: [String] = []
        var index = startIndex
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard isBlockquoteLine(trimmed) else { break }
            quoteLines.append(
                trimmed.dropFirst()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            index += 1
        }
        return (quoteLines.joined(separator: "\n"), index)
    }

    private static func parseUnorderedList(
        lines: [String],
        startIndex: Int
    ) -> (items: [String], nextIndex: Int) {
        var items: [String] = []
        var index = startIndex
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = unorderedListItem(trimmed) else { break }
            items.append(item)
            index += 1
        }
        return (items, index)
    }

    private static func unorderedListItem(_ trimmed: String) -> String? {
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            let item = trimmed.dropFirst(marker.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return item.isEmpty ? nil : item
        }
        return nil
    }

    private static func parseOrderedList(
        lines: [String],
        startIndex: Int
    ) -> (items: [String], nextIndex: Int) {
        var items: [String] = []
        var index = startIndex
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = orderedListItem(trimmed) else { break }
            items.append(item)
            index += 1
        }
        return (items, index)
    }

    private static func orderedListItem(_ trimmed: String) -> String? {
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let prefix = trimmed[..<dotIndex]
        guard !prefix.isEmpty,
              prefix.allSatisfy({ $0.isNumber }) else { return nil }
        let afterDot = trimmed[trimmed.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        let item = afterDot.trimmingCharacters(in: .whitespacesAndNewlines)
        return item.isEmpty ? nil : item
    }

    private static func parseParagraph(
        lines: [String],
        startIndex: Int
    ) -> (text: String, nextIndex: Int) {
        var paragraphLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if index != startIndex {
                if parseCodeBlock(lines: lines, startIndex: index) != nil ||
                    parseTable(lines: lines, startIndex: index) != nil ||
                    parseHeading(trimmed) != nil ||
                    isBlockquoteLine(trimmed) ||
                    unorderedListItem(trimmed) != nil ||
                    orderedListItem(trimmed) != nil {
                    break
                }
            }
            paragraphLines.append(trimmed)
            index += 1
        }

        return (paragraphLines.joined(separator: "\n"), index)
    }
}

struct HermesChatMarkdownView: View {
    let text: String
    let isStreaming: Bool

    private var blocks: [HermesMarkdownBlock] {
        HermesChatMarkdownParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, showsCursor: isStreaming && index == blocks.count - 1)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: HermesMarkdownBlock, showsCursor: Bool) -> some View {
        switch block {
        case .paragraph(let text):
            markdownText(text, showsCursor: showsCursor)
        case .heading(let level, let text):
            markdownText(text, showsCursor: showsCursor)
                .font(headingFont(level: level))
                .padding(.top, level <= 2 ? 2 : 0)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        markdownText(item, showsCursor: showsCursor && index == items.count - 1)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        markdownText(item, showsCursor: showsCursor && index == items.count - 1)
                    }
                }
            }
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                markdownText(text, showsCursor: showsCursor)
                    .foregroundStyle(.secondary)
            }
        case .codeBlock(let language, let code):
            HermesMarkdownCodeBlockView(language: language, code: code, showsCursor: showsCursor)
        case .table(let table):
            HermesMarkdownTableView(table: table)
        }
    }

    private func markdownText(_ text: String, showsCursor: Bool) -> Text {
        let displayText = text + (showsCursor ? "▍" : "")
        if let attributed = try? AttributedString(markdown: displayText) {
            return Text(attributed)
        }
        return Text(displayText)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .headline
        case 2:
            return .subheadline.weight(.semibold)
        default:
            return .callout.weight(.semibold)
        }
    }
}

private struct HermesMarkdownCodeBlockView: View {
    let language: String?
    let code: String
    let showsCursor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code + (showsCursor ? "▍" : ""))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18))
        )
    }
}

private struct HermesMarkdownTableView: View {
    let table: HermesMarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        cell(header, isHeader: true)
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<table.headers.count, id: \.self) { index in
                            cell(index < row.count ? row[index] : "", isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.20))
            )
        }
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
            .font(isHeader ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(isHeader ? .secondary : .primary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 92, maxWidth: 180, alignment: .topLeading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isHeader ? Color.secondary.opacity(0.12) : Color.clear)
            .border(Color.secondary.opacity(0.14), width: 0.5)
    }
}
