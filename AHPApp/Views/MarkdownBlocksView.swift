import UIKit
import Foundation
import SwiftUI

/// One block of a markdown document.
///
/// `AttributedString(markdown:)` with `.inlineOnlyPreservingWhitespace` — what
/// upstream rendered replies with — handles emphasis, code spans and links but
/// leaves block syntax as literal text, so `### Heading` showed its hashes.
/// Parsing the full syntax instead gives presentation intents that `Text`
/// cannot lay out, so blocks are split here and each is drawn natively, with
/// inline markdown still parsed inside it.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// `ordinal` is nil for a bullet. `indent` counts nesting levels.
    case listItem(ordinal: String?, indent: Int, text: String)
    /// A `>` quote holds blocks of its own: headings, lists, paragraphs.
    case quote([MarkdownBlock])
    case code(language: String?, text: String)
    case table(header: [String], rows: [[String]])
    case rule

    /// Splits `source` into blocks. Tolerant by design: replies stream in, so a
    /// code fence may not be closed yet, and anything unrecognised is a paragraph.
    static func parse(_ source: String) -> [MarkdownBlock] {
        parseBlocks(resolvingReferenceLinks(source))
    }

    private static func parseBlocks(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0

        // Lines of one paragraph are one run of text: a newline inside it is
        // just where the author wrapped, so it reads as a space.
        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(joined(paragraph)))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code: everything up to the closing fence, or the end.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    body.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, text: body.joined(separator: "\n")))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // A line under a list item that starts no block of its own
            // continues that item's text.
            if paragraph.isEmpty, case .listItem(let ordinal, let indent, let text)? = blocks.last,
               i > 0, !lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty,
               !startsBlock(line) {
                blocks[blocks.count - 1] = .listItem(ordinal: ordinal, indent: indent, text: text + " " + trimmed)
                i += 1
                continue
            }

            if let heading = headingLevel(trimmed) {
                flushParagraph()
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: heading, text: text))
                i += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            // A pipe table needs its delimiter row (`|---|:--|`) right after the header.
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableDelimiter(lines[i + 1]) {
                flushParagraph()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(tableCells(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            if let item = listItem(line) {
                flushParagraph()
                blocks.append(item)
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let q = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                    quoted.append(q.hasPrefix(" ") ? String(q.dropFirst()) : String(q))
                    i += 1
                }
                blocks.append(.quote(parseBlocks(quoted.joined(separator: "\n"))))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func joined(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    /// Whether `line` begins a block rather than continuing text.
    private static func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return headingLevel(trimmed) != nil || isRule(trimmed) || listItem(line) != nil
            || trimmed.hasPrefix(">") || trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            || trimmed.hasPrefix("|")
    }

    /// `[text][id]` and `[id][]` → `[text](url)`, using `[id]: url` lines,
    /// which are removed. Inline-only parsing never sees the definitions.
    static func resolvingReferenceLinks(_ source: String) -> String {
        guard source.contains("]:") else { return source }
        var definitions: [String: String] = [:]
        var kept: [String] = []
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), let close = trimmed.range(of: "]:"),
               !trimmed[trimmed.index(after: trimmed.startIndex)..<close.lowerBound].contains("]") {
                let id = trimmed[trimmed.index(after: trimmed.startIndex)..<close.lowerBound].lowercased()
                let rest = trimmed[close.upperBound...].trimmingCharacters(in: .whitespaces)
                if let url = rest.split(separator: " ").first, !id.isEmpty {
                    definitions[id] = String(url).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                    continue
                }
            }
            kept.append(line)
        }
        guard !definitions.isEmpty else { return source }
        var text = kept.joined(separator: "\n")
        for (id, url) in definitions {
            // [text][id], matched case-insensitively on the id.
            let pattern = "\\[([^\\]]+)\\]\\[(" + NSRegularExpression.escapedPattern(for: id) + ")?\\]"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            var result = ""
            var last = text.startIndex
            for match in regex.matches(in: text, range: range) {
                guard let whole = Range(match.range, in: text), let label = Range(match.range(at: 1), in: text) else { continue }
                let hasId = match.range(at: 2).location != NSNotFound
                // `[text][]` only matches when the text itself is the id.
                if !hasId, text[label].lowercased() != id { continue }
                result += text[last..<whole.lowerBound] + "[\(text[label])](\(url))"
                last = whole.upperBound
            }
            text = result + text[last...]
        }
        return text
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        // "#hashtag" is not a heading; "#" alone is an empty one.
        return rest.isEmpty || rest.first == " " ? hashes : nil
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    private static func tableCells(_ line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") { body = body.dropLast() }
        return body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
        let width = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let rest = line.dropFirst(leading.count)
        for marker in ["- ", "* ", "+ "] where rest.hasPrefix(marker) {
            return .listItem(ordinal: nil, indent: width / 2, text: String(rest.dropFirst(2)))
        }
        let digits = rest.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 9 {
            let after = rest.dropFirst(digits.count)
            if after.hasPrefix(". ") || after.hasPrefix(") ") {
                return .listItem(ordinal: "\(digits).", indent: width / 2, text: String(after.dropFirst(2)))
            }
        }
        return nil
    }
}

/// Draws a markdown document block by block.
///
/// Text blocks are `SelectableText`, so a range can be selected (and quoted
/// into a reply); a selection stays within one block.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    /// The text's colour. A quote passes secondary: `foregroundStyle` does not
    /// reach into a UIKit text view.
    var textColor: UIColor = .label

    init(_ source: String) {
        self.blocks = MarkdownBlock.parse(source)
    }

    init(blocks: [MarkdownBlock], textColor: UIColor = .label) {
        self.blocks = blocks
        self.textColor = textColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            SelectableText(Self.selectableInline(
                text, font: Self.headingUIFont(level), style: Self.headingStyle(level), color: textColor
            ))
                .padding(.top, level <= 2 ? 6 : 2)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            SelectableText(Self.selectableInline(text, color: textColor))
        case .listItem(let ordinal, let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ordinal ?? (indent == 0 ? "•" : "◦"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                SelectableText(Self.selectableInline(text, color: textColor))
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let inner):
            MarkdownBlocksView(blocks: inner, textColor: .secondaryLabel)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.tertiary)
                        .frame(width: 3)
                }
        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                SelectableText(NSAttributedString(string: text, attributes: [
                    .font: UIFont.monospacedSystemFont(
                        ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular
                    ),
                    .foregroundColor: UIColor.systemOrange,
                ]))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        case .table(let header, let rows):
            // Fixed-width columns: cells wrap inside them and every row is
            // as tall as its tallest cell. Wide tables scroll sideways.
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    tableRow(header, bold: true)
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        tableRow(row, bold: false)
                    }
                }
                .padding(10)
            }
            .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        }
    }

    private func tableRow(_ cells: [String], bold: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(Self.inline(cell, style: .subheadline))
                    .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                    .frame(width: Self.columnWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static let columnWidth: CGFloat = 180

    /// Emphasis, code spans and links inside a block; the raw text if that fails.
    ///
    /// Code spans are orange, like code blocks, and a size smaller than the
    /// text around them: monospaced letters are wider, so at the same point
    /// size they read as bigger. `style` is the surrounding text's style.
    static func inline(_ text: String, style: UIFont.TextStyle = .body) -> AttributedString {
        guard var parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return AttributedString(text) }
        let codeFont = Font.system(
            size: UIFont.preferredFont(forTextStyle: style).pointSize * inlineCodeScale,
            design: .monospaced
        )
        for run in parsed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            parsed[run.range].foregroundColor = codeColor
            parsed[run.range].font = codeFont
        }
        return parsed
    }

    /// `inline` for UIKit: the same emphasis, code spans and links, as
    /// attributes a `UITextView` draws. `font` is the surrounding text's font
    /// and `style` its text style, which sizes code spans.
    static func selectableInline(
        _ text: String,
        font: UIFont = .preferredFont(forTextStyle: .body),
        style: UIFont.TextStyle = .body,
        color: UIColor = .label
    ) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
        let codeFont = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: style).pointSize * inlineCodeScale,
            weight: .regular
        )
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font
            var traits = font.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                runFont = UIFont(descriptor: descriptor, size: 0)
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color]
            if intent.contains(.code) {
                attributes[.font] = codeFont
                attributes[.foregroundColor] = UIColor.systemOrange
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
            }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }

    private static func headingUIFont(_ level: Int) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: headingStyle(level)).pointSize
        return .systemFont(ofSize: size, weight: level == 1 ? .bold : .semibold)
    }

    /// Inline code relative to its surrounding text: 17 pt body → 15 pt.
    static let inlineCodeScale: CGFloat = 0.88

    private static func headingStyle(_ level: Int) -> UIFont.TextStyle {
        switch level {
        case 1: .title2
        case 2: .title3
        case 3: .headline
        default: .subheadline
        }
    }

    static let codeColor = Color.orange
}
