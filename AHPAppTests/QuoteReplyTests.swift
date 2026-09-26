import Foundation
import Testing
import UIKit
@testable import AHPApp

@MainActor
struct QuoteReplyTests {
    @Test func aSelectionBecomesABlockquoteWithRoomToReply() {
        #expect(QuoteReply.draft("", quoting: "stale-tunnel problem") == "> stale-tunnel problem\n\n")
    }

    @Test func everyLineIsQuotedAndBlankLinesStayInTheQuote() {
        #expect(QuoteReply.quoted("one\n\ntwo\n") == "> one\n>\n> two\n\n")
    }

    @Test func aQuoteGoesAfterWhatIsAlreadyTyped() {
        let first = QuoteReply.draft("", quoting: "first")
        #expect(QuoteReply.draft(first + "my answer\n", quoting: "second")
            == "> first\n\nmy answer\n\n> second\n\n")
    }

    @Test func selectableTextKeepsEmphasisCodeAndLinks() {
        let text = MarkdownBlocksView.selectableInline("**bold** `code` [site](https://example.com)")
        #expect(text.string == "bold code site")
        let bold = text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(text.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? UIColor == .systemOrange)
        #expect(text.attribute(.link, at: 10, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
    }
}
