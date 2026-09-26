import SwiftUI
import UIKit

/// A file on the host, read with `resourceRead`: markdown rendered (with the
/// source a tap away), images shown, anything else as numbered text, scrolled
/// to `line` when a link named one. Links inside a markdown file resolve
/// against that file's own folder and open here too.
struct FileViewerView: View {
    let link: FileLink

    @Environment(AppStore.self) private var store
    @State private var file: HostFile?
    @State private var error: String?
    @State private var showsSource = false
    @State private var followed: FileLink?

    /// Beyond this many lines only the start is drawn; a phone scrolling a
    /// 50,000-line log helps no one.
    private static let lineLimit = 5_000

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Can't open this file", systemImage: "doc.questionmark", description: Text(error))
            } else if let file {
                content(file)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(FolderURI.name(link.uri))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if file?.isMarkdown == true {
                ToolbarItem(placement: .primaryAction) {
                    Button(showsSource ? "Rendered" : "Source") { showsSource.toggle() }
                }
            }
        }
        .navigationDestination(item: $followed) { next in
            FileViewerView(link: next)
        }
        .task(id: link.uri) { await load() }
    }

    @ViewBuilder
    private func content(_ file: HostFile) -> some View {
        if let image = UIImage(data: file.data), file.contentType?.hasPrefix("text/") != true {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
            }
        } else if let text = file.text {
            if file.isMarkdown, !showsSource {
                ScrollView {
                    MarkdownBlocksView(text)
                        .padding()
                }
                .environment(\.openURL, OpenURLAction { url in
                    guard let next = FileLink.resolve(url.absoluteString, base: folder(of: file.uri)) else {
                        return .systemAction
                    }
                    followed = next
                    return .handled
                })
            } else {
                NumberedText(text: text, line: link.line, limit: Self.lineLimit)
            }
        } else {
            ContentUnavailableView(
                "No preview",
                systemImage: "doc",
                description: Text("\(file.contentType ?? "Binary file"), \(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))")
            )
        }
    }

    private func folder(of uri: String) -> String? {
        FolderURI.parent(uri)
    }

    private func load() async {
        do {
            file = try await store.readFile(link.uri)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Monospaced lines with numbers, scrolled to `line` and highlighting it.
private struct NumberedText: View {
    let lines: [Substring]
    let line: Int?
    let truncated: Bool
    /// The widest row, measured up front. A lazy stack only sizes the rows it
    /// has drawn, so in a sideways-scrolling view its width changed as longer
    /// lines came into view, and the whole file sat shifted right.
    let contentWidth: CGFloat

    init(text: String, line: Int?, limit: Int) {
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        self.lines = Array(all.prefix(limit))
        self.truncated = all.count > limit
        let font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular
        )
        let numbers = String(repeating: "0", count: String(lines.count).count)
        let longest = lines.max { $0.count < $1.count }.map(String.init) ?? ""
        func measure(_ s: String) -> CGFloat {
            ceil((s as NSString).size(withAttributes: [.font: font]).width)
        }
        // Numbers, the 12 pt gap, the code, and 12 pt either side.
        self.contentWidth = measure(numbers) + 12 + measure(longest) + 24
        self.line = line
    }

    var body: some View {
        let width = String(lines.count).count
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, text in
                        // One line each: numbers never wrap, code scrolls sideways.
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(index + 1).leftPadded(to: width))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .fixedSize()
                            Text(text.isEmpty ? " " : String(text))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1)
                        .background(index + 1 == line ? Color.yellow.opacity(0.25) : .clear)
                        .id(index + 1)
                    }
                    if truncated {
                        Text("Showing the first \(lines.count) lines")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                .frame(minWidth: contentWidth, alignment: .leading)
                .padding(.vertical, 8)
                .textSelection(.enabled)
            }
            .onAppear {
                if let line { proxy.scrollTo(line, anchor: UnitPoint(x: 0, y: 0.4)) }
            }
        }
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }
}
