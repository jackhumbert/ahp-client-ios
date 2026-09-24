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
    case quote(String)
    case code(language: String?, text: String)
    case table(header: [String], rows: [[String]])
    case rule

    /// Splits `source` into blocks. Tolerant by design: replies stream in, so a
    /// code fence may not be closed yet, and anything unrecognised is a paragraph.
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
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
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
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
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]

    init(_ source: String) {
        self.blocks = MarkdownBlock.parse(source)
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
            Text(Self.inline(text))
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(Self.inline(text))
        case .listItem(let ordinal, let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ordinal ?? (indent == 0 ? "•" : "◦"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(Self.inline(text))
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            Text(Self.inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.tertiary)
                        .frame(width: 3)
                }
        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(Self.inline(cell)).font(.subheadline.weight(.semibold))
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(Self.inline(cell)).font(.subheadline)
                            }
                        }
                    }
                }
                .padding(10)
            }
            .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.bold)
        case 2: .title3.weight(.semibold)
        case 3: .headline
        default: .subheadline.weight(.semibold)
        }
    }

    /// Emphasis, code spans and links inside a block; the raw text if that fails.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
