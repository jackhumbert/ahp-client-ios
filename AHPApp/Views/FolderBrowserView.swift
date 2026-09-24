import SwiftUI

/// Folder URIs as hosts and brokers write them.
///
/// - `file:///Users/me/repo`: a host on one machine.
/// - `file://<machine>/Users/me/repo`, `file://studio/D:/work`: the deployed
///   broker, whose authority names the machine.
/// - `ahp-file:///<machine>/<path under its root>` and
///   `ahp-file://<machine>/<absolute path>`: agent-host-broker's own scheme,
///   where `ahp-file:///` itself lists the machines.
enum FolderURI {
    static let brokerScheme = "ahp-file"
    /// The broker's list of machines.
    static let brokerRoot = "ahp-file:///"

    /// The path part, for showing: `/Users/me/repo`, `D:/work`.
    static func path(_ uri: String) -> String {
        guard let url = URL(string: uri), let scheme = url.scheme else { return uri }
        var path = url.path(percentEncoded: false)
        if scheme == brokerScheme, (url.host() ?? "").isEmpty {
            // `ahp-file:///<machine>/<rel>`: the first segment is the machine.
            let parts = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            path = parts.count > 1 ? "/" + parts[1] : "/"
        } else if scheme != "file", scheme != brokerScheme {
            return uri
        }
        // `/D:/work` is a Windows drive path; the leading slash is URI syntax.
        if path.count > 2, path.hasPrefix("/"), path.dropFirst(2).first == ":" {
            return String(path.dropFirst())
        }
        return path.isEmpty ? "/" : path
    }

    /// The machine this URI is on, when it names one.
    static func machine(_ uri: String) -> String? {
        guard let url = URL(string: uri) else { return nil }
        if let host = url.host(percentEncoded: false), !host.isEmpty { return host }
        if url.scheme == brokerScheme {
            return url.path(percentEncoded: false).split(separator: "/").first.map(String.init)
        }
        return nil
    }

    static func name(_ uri: String) -> String {
        if uri == brokerRoot { return "Machines" }
        let path = path(uri)
        if path == "/", let machine = machine(uri) { return machine }
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    static func child(_ uri: String, _ name: String) -> String {
        guard let url = URL(string: uri) else { return uri + "/" + name }
        return trimmed(url.appending(path: name, directoryHint: .isDirectory).absoluteString)
    }

    /// Nil at the top: the filesystem root, a drive, or the broker's machine list.
    static func parent(_ uri: String) -> String? {
        guard uri != brokerRoot, let url = URL(string: uri) else { return nil }
        if url.scheme == brokerScheme, (url.host() ?? "").isEmpty {
            // A machine's root goes up to the list of machines.
            return path(uri) == "/" ? brokerRoot : trimmed(url.deletingLastPathComponent().absoluteString)
        }
        let path = path(uri)
        guard path != "/", !(path.count <= 3 && path.contains(":")) else { return nil }
        return trimmed(url.deletingLastPathComponent().absoluteString)
    }

    /// Without the trailing slash URL APIs add, so a chosen folder reads the
    /// same as the ones hosts send. The broker root keeps its slash.
    private static func trimmed(_ uri: String) -> String {
        uri != brokerRoot && uri.hasSuffix("/") && !uri.hasSuffix(":///") ? String(uri.dropLast()) : uri
    }
}

/// Walk the host's folders (`resourceList`) and choose one, the way the
/// system's own pickers feel: each folder is pushed (swipe back, back buttons
/// named after the parent), a search field filters the folder in view, rows
/// swipe to choose or pin, and files are listed dimmed so you can tell where
/// you are without being able to pick one.
///
/// Apple's document picker cannot do this: it only shows the phone's own
/// locations, and the folders an agent works in exist only on its host.
struct FolderBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    /// The folder the stack starts at; "Enclosing folder" moves it up.
    @State private var root: String
    @State private var path: [String] = []
    @AppStorage("folderBrowserShowsHidden") private var showsHidden = false

    let onChoose: (String) -> Void

    init(start: String, onChoose: @escaping (String) -> Void) {
        _root = State(initialValue: start)
        self.onChoose = onChoose
    }

    var body: some View {
        NavigationStack(path: $path) {
            list(root, isRoot: true)
                .navigationDestination(for: String.self) { uri in
                    list(uri, isRoot: false)
                }
        }
    }

    private func list(_ uri: String, isRoot: Bool) -> some View {
        FolderListView(
            uri: uri,
            isRoot: isRoot,
            showsHidden: $showsHidden,
            choose: { chosen in
                onChoose(chosen)
                dismiss()
            },
            cancel: { dismiss() },
            goUp: {
                // A host only serves the tree under its root, so the stack
                // starts where it can list; going above re-roots it.
                if let parent = FolderURI.parent(root) {
                    root = parent
                    path = []
                }
            }
        )
        // A new identity per folder, so each level loads its own listing.
        .id(uri)
    }
}

/// One folder's contents.
private struct FolderListView: View {
    @Environment(AppStore.self) private var store

    let uri: String
    let isRoot: Bool
    @Binding var showsHidden: Bool
    let choose: (String) -> Void
    let cancel: () -> Void
    let goUp: () -> Void

    @State private var entries: [FolderEntry] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var query = ""

    private var isMachineList: Bool { uri == FolderURI.brokerRoot }

    private var visible: [FolderEntry] {
        entries.filter { entry in
            (showsHidden || !entry.isHidden)
                && (query.isEmpty || entry.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List {
            if isRoot, query.isEmpty, !store.pinnedFolders.isEmpty {
                Section("Pinned") {
                    ForEach(store.pinnedFolders, id: \.self) { pinned in
                        folderRow(pinned, title: FolderURI.name(pinned), subtitle: pinnedSubtitle(pinned))
                    }
                }
            }

            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if visible.isEmpty {
                    Text(query.isEmpty ? "Empty folder" : "No matches")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visible, id: \.name) { entry in
                        if entry.isDirectory {
                            folderRow(FolderURI.child(uri, entry.name), title: entry.name, subtitle: nil)
                        } else {
                            // Shown for orientation only: a working directory is a folder.
                            Label(entry.name, systemImage: "doc")
                                .foregroundStyle(.tertiary)
                                .accessibilityHint("A file; only folders can be chosen")
                        }
                    }
                }
            } header: {
                header
            }
        }
        .searchable(text: $query, prompt: "Filter this folder")
        .refreshable { await load() }
        .navigationTitle(FolderURI.name(uri))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task { await load() }
    }

    private func folderRow(_ folder: String, title: String, subtitle: String?) -> some View {
        NavigationLink(value: folder) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: store.isPinned(folder) ? "folder.fill" : "folder")
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .swipeActions(edge: .leading) {
            if folder != FolderURI.brokerRoot {
                Button("Choose") { choose(folder) }
                    .tint(.accentColor)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(store.isPinned(folder) ? "Unpin" : "Pin") { store.togglePin(folder) }
                .tint(.orange)
        }
    }

    private func pinnedSubtitle(_ folder: String) -> String {
        [FolderURI.path(folder), FolderURI.machine(folder).map { "on \($0)" }]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    @ViewBuilder
    private var header: some View {
        if isMachineList {
            Text("Choose a machine").textCase(nil)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(FolderURI.path(uri))
                    .font(.footnote.monospaced())
                    .textCase(nil)
                    .lineLimit(2)
                    .truncationMode(.head)
                if let machine = FolderURI.machine(uri) {
                    Text("on \(machine)")
                        .textCase(nil)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isRoot {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            // Enabled even when listing failed: a host may not offer browsing
            // (the Claude host on Windows doesn't) while the folder itself is
            // still a fine place to work. The list of machines is a place to
            // start, not to work.
            Button("Choose") { choose(uri) }
                .disabled(isMachineList)
        }
        ToolbarItem(placement: .bottomBar) {
            Menu {
                Toggle("Show Hidden Folders", systemImage: "eye", isOn: $showsHidden)
                if !isMachineList {
                    Button(
                        store.isPinned(uri) ? "Unpin This Folder" : "Pin This Folder",
                        systemImage: store.isPinned(uri) ? "pin.slash" : "pin"
                    ) {
                        store.togglePin(uri)
                    }
                }
                if isRoot, let parent = FolderURI.parent(uri) {
                    Button("Enclosing Folder (\(FolderURI.name(parent)))", systemImage: "arrow.up", action: goUp)
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
    }

    private func load() async {
        do {
            entries = try await store.listFolder(uri)
            error = nil
        } catch {
            entries = []
            self.error = "Can't open this folder: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
