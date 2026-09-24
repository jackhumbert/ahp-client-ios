import Testing
@testable import AHPApp

/// Replies stream in, so the parser sees every prefix of a document; these pin
/// the block shapes Claude actually writes.
struct MarkdownBlockTests {
    @Test func headingsAreBlocksNotLiteralHashes() {
        #expect(MarkdownBlock.parse("### Findings\nThe repo is fine.") == [
            .heading(level: 3, text: "Findings"),
            .paragraph("The repo is fine."),
        ])
    }

    @Test func aHashtagIsNotAHeading() {
        #expect(MarkdownBlock.parse("#hashtag") == [.paragraph("#hashtag")])
    }

    @Test func listsKeepTheirMarkersAndNesting() {
        #expect(MarkdownBlock.parse("- one\n  - nested\n2. two") == [
            .listItem(ordinal: nil, indent: 0, text: "one"),
            .listItem(ordinal: nil, indent: 1, text: "nested"),
            .listItem(ordinal: "2.", indent: 0, text: "two"),
        ])
    }

    @Test func anUnclosedFenceIsStillCodeWhileStreaming() {
        #expect(MarkdownBlock.parse("```swift\nlet x = 1\n# not a heading") == [
            .code(language: "swift", text: "let x = 1\n# not a heading"),
        ])
    }

    @Test func pipeTablesNeedTheirDelimiterRow() {
        #expect(MarkdownBlock.parse("| a | b |\n|---|:-:|\n| 1 | 2 |") == [
            .table(header: ["a", "b"], rows: [["1", "2"]]),
        ])
        #expect(MarkdownBlock.parse("| just | pipes |") == [.paragraph("| just | pipes |")])
    }

    @Test func quotesAndRules() {
        #expect(MarkdownBlock.parse("> said\n> twice\n\n---") == [.quote("said\ntwice"), .rule])
    }
}
