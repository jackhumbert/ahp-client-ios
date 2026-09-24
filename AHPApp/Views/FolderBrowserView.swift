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

/// Walk the host's folders (`resourceList`) and choose one.
///
/// A host only lets you see inside the root it serves; stepping above it
/// fails, and the error is shown rather than hidden, with Up still available.
struct FolderBrowserView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var current: String
    @State private var folders: [String] = []
    @State private var error: String?
    @State private var isLoading = false

    let onChoose: (String) -> Void

    init(start: String, onChoose: @escaping (String) -> Void) {
        _current = State(initialValue: start)
        self.onChoose = onChoose
    }

    var body: some View {
        List {
            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if folders.isEmpty {
                    Text("No folders inside")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(folders, id: \.self) { name in
                        Button {
                            current = FolderURI.child(current, name)
                        } label: {
                            Label(name, systemImage: "folder")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            } header: {
                if current == FolderURI.brokerRoot {
                    Text("Choose a machine").textCase(nil)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FolderURI.path(current))
                            .font(.footnote.monospaced())
                            .textCase(nil)
                            .lineLimit(2)
                            .truncationMode(.head)
                        if let machine = FolderURI.machine(current) {
                            Text("on \(machine)")
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle(FolderURI.name(current))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                // Enabled even when listing failed: a host may not offer
                // browsing (the Claude host on Windows doesn't) while the
                // folder itself is still a fine place to work.
                Button("Choose") {
                    onChoose(current)
                    dismiss()
                }
                // The list of machines is a place to start, not to work.
                .disabled(current == FolderURI.brokerRoot)
            }
            ToolbarItem(placement: .bottomBar) {
                if let parent = FolderURI.parent(current) {
                    Button {
                        current = parent
                    } label: {
                        Label("Up to \(FolderURI.name(parent))", systemImage: "arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .task(id: current) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            folders = try await store.listFolders(current)
            error = nil
        } catch {
            folders = []
            self.error = "Can't open this folder: \(error.localizedDescription)"
        }
    }
}
