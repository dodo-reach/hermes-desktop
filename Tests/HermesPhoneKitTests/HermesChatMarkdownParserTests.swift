import Testing

@testable import HermesPhoneKit

struct HermesChatMarkdownParserTests {
    @Test
    func parsesMarkdownTables() {
        let blocks = HermesChatMarkdownParser.parse(
            """
            | Tool | Status |
            | --- | --- |
            | Search | Done |
            | Build | Running |
            """
        )

        #expect(blocks == [
            .table(
                HermesMarkdownTable(
                    headers: ["Tool", "Status"],
                    rows: [
                        ["Search", "Done"],
                        ["Build", "Running"]
                    ]
                )
            )
        ])
    }

    @Test
    func parsesCodeFencesWithoutTreatingPipesAsTables() {
        let blocks = HermesChatMarkdownParser.parse(
            """
            ```swift
            let value = left | right
            ```
            """
        )

        #expect(blocks == [
            .codeBlock(language: "swift", code: "let value = left | right")
        ])
    }

    @Test
    func parsesHeadingsListsAndParagraphs() {
        let blocks = HermesChatMarkdownParser.parse(
            """
            ## Plan

            - Parse markdown
            - Render tables

            Ship it.
            """
        )

        #expect(blocks == [
            .heading(level: 2, text: "Plan"),
            .unorderedList(["Parse markdown", "Render tables"]),
            .paragraph("Ship it.")
        ])
    }

    @Test
    func parsesOrderedListsAndBlockquotes() {
        let blocks = HermesChatMarkdownParser.parse(
            """
            > Rich output should stay chat-sized.
            > Tables can scroll.

            1. Build
            2. Test
            """
        )

        #expect(blocks == [
            .blockquote("Rich output should stay chat-sized.\nTables can scroll."),
            .orderedList(["Build", "Test"])
        ])
    }
}
