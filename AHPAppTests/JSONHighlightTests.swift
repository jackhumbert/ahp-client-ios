import Foundation
import SwiftUI
import Testing
@testable import AHPApp

@MainActor
struct JSONHighlightTests {
    private func plain(_ text: String) -> String? {
        JSONHighlight.highlighted(text).map { String($0.characters) }
    }

    @Test func toolArgumentsAreIndentedInTheirOwnOrder() {
        #expect(plain(#"{"command": "ls -la", "description": "List files", "n": 3}"#) == """
        {
          "command": "ls -la",
          "description": "List files",
          "n": 3
        }
        """)
    }

    @Test func nestingEmptyContainersAndEscapedQuotes() {
        #expect(plain(#"[{"a":[],"b":{},"c":"say \"hi\"","d":[true,null]}]"#) == """
        [
          {
            "a": [],
            "b": {},
            "c": "say \\"hi\\"",
            "d": [
              true,
              null
            ]
          }
        ]
        """)
    }

    @Test func keysAndValuesAreColouredApart() throws {
        let text = try #require(JSONHighlight.highlighted(#"{"k": "v", "n": 1.5, "b": false}"#))
        func color(of token: String) -> Color? {
            text.range(of: token).flatMap { text[$0].foregroundColor }
        }
        #expect(color(of: #""k""#) == JSONHighlight.keyColor)
        #expect(color(of: #""v""#) == JSONHighlight.stringColor)
        #expect(color(of: "1.5") == JSONHighlight.numberColor)
        #expect(color(of: "false") == JSONHighlight.keywordColor)
    }

    @Test func anythingElseIsLeftAlone() {
        #expect(JSONHighlight.highlighted("total 8\ndrwxr-xr-x  2 me") == nil)
        #expect(JSONHighlight.highlighted(#"{"unterminated": "#) == nil)
        #expect(JSONHighlight.highlighted("42") == nil)
    }
}
