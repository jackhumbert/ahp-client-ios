import Foundation
import SwiftUI

/// Pretty-printed, coloured JSON for tool inputs and outputs.
///
/// Tools take their arguments as one line of JSON and often answer in it, so
/// the detail sheet showed `{"command": "…", "description": "…"}` run
/// together. Formatted by re-flowing the original tokens rather than
/// round-tripping through `JSONSerialization`, which would reorder the keys
/// and rewrite numbers.
enum JSONHighlight {
    /// Past this, formatting costs more than it helps.
    static let sizeLimit = 200_000

    /// `text` indented and coloured, when it is a JSON object or array;
    /// nil for anything else, which is shown as it came.
    static func highlighted(_ text: String) -> AttributedString? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= sizeLimit,
              let first = trimmed.first, first == "{" || first == "[",
              let data = trimmed.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return nil }
        return format(Array(trimmed))
    }

    static let keyColor = Color(.systemBlue)
    static let stringColor = Color(.systemGreen)
    static let numberColor = Color.orange
    static let keywordColor = Color(.systemPurple)
    static let punctuationColor = Color.secondary

    private static func format(_ chars: [Character]) -> AttributedString {
        var out = AttributedString()
        var depth = 0
        var i = 0

        func append(_ s: String, _ color: Color) {
            var piece = AttributedString(s)
            piece.foregroundColor = color
            out += piece
        }
        func newline() {
            out += AttributedString("\n" + String(repeating: "  ", count: depth))
        }
        func nextSignificant(after index: Int) -> Character? {
            var j = index
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            return j < chars.count ? chars[j] : nil
        }

        while i < chars.count {
            let c = chars[i]
            switch c {
            case _ where c.isWhitespace:
                i += 1
            case "\"":
                var j = i + 1
                while j < chars.count, chars[j] != "\"" {
                    j += chars[j] == "\\" ? 2 : 1
                }
                let literal = String(chars[i...min(j, chars.count - 1)])
                i = j + 1
                append(literal, nextSignificant(after: i) == ":" ? keyColor : stringColor)
            case "{", "[":
                let close: Character = c == "{" ? "}" : "]"
                append(String(c), punctuationColor)
                i += 1
                if nextSignificant(after: i) == close {
                    // An empty container stays on one line.
                    while chars[i] != close { i += 1 }
                    append(String(close), punctuationColor)
                    i += 1
                } else {
                    depth += 1
                    newline()
                }
            case "}", "]":
                depth -= 1
                newline()
                append(String(c), punctuationColor)
                i += 1
            case ",":
                append(",", punctuationColor)
                newline()
                i += 1
            case ":":
                append(": ", punctuationColor)
                i += 1
            default:
                var j = i
                while j < chars.count, !chars[j].isWhitespace, !",:]}".contains(chars[j]) { j += 1 }
                let literal = String(chars[i..<j])
                i = j
                append(literal, ["true", "false", "null"].contains(literal) ? keywordColor : numberColor)
            }
        }
        return out
    }
}

/// Monospaced tool text: formatted and coloured when it is JSON.
struct ToolText: View {
    let text: String

    var body: some View {
        Group {
            if let json = JSONHighlight.highlighted(text) {
                Text(json)
            } else {
                Text(text)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }
}
