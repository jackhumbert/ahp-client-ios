import AgentHostProtocol
import SwiftUI

/// Agent/model picker for creating a new session.
struct AgentPicker: View {
    @Environment(AppStore.self) private var store
    @State private var selectedProvider: String = ""
    @State private var selectedModel: String = ""
    @State private var workingDirectory: String = ""
    /// The host's settings for the chosen agent (`resolveSessionConfig`).
    @State private var configSchema: SessionConfigSchema?
    @State private var configValues: [String: AnyCodable] = [:]
    /// Bumped per request so a slow, stale answer never overwrites a newer one.
    @State private var resolveGeneration = 0
    @State private var showingBrowser = false
    /// True while `workingDirectory` holds what the app filled in rather than
    /// what the user chose, so switching agents may replace it.
    @State private var directoryWasAutofilled = false

    private var recentFolders: [String] {
        selectedProvider.isEmpty ? [] : store.recentFolders(for: selectedProvider)
    }

    /// The host's default folder, unless it is agent-host-broker's list of
    /// machines (`ahp-file:///`): a place to start browsing, not to work.
    private var usableDefaultDirectory: String? {
        store.defaultDirectory.flatMap { $0 == FolderURI.brokerRoot ? nil : $0 }
    }

    /// Where Browse opens: the folder already in the field, else the host's
    /// default, else this agent's latest folder. A broker in front of several
    /// machines has no default, and a bare path is not routable through it.
    private var browseStart: String? {
        if let typed = trimmedDirectory, FolderURI.machine(typed) != nil || typed.hasPrefix("file:") {
            return typed
        }
        if let start = store.defaultDirectory ?? recentFolders.first { return start }
        // agent-host-broker lists its machines at `ahp-file:///`; its URIs in
        // any session say this server is one.
        return store.speaksBrokerFolders ? FolderURI.brokerRoot : nil
    }

    /// Optional pre-filled working directory (e.g. from a folder section).
    var initialDirectory: String?
    let onSelect: (
        _ provider: String,
        _ model: String?,
        _ workingDirectory: String?,
        _ config: [String: AnyCodable]
    ) -> Void

    private var trimmedDirectory: String? {
        let dir = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return dir.isEmpty ? nil : dir
    }

    private var selectedAgent: AgentInfo? {
        store.agents.first { $0.provider == selectedProvider }
    }

    private var canCreate: Bool {
        !selectedProvider.isEmpty
    }

    var body: some View {
        Form {
            Section {
                Picker("Agent", selection: $selectedProvider) {
                    Text("Select an agent").tag("")
                    ForEach(store.agents, id: \.provider) { agent in
                        Text(agent.displayName).tag(agent.provider)
                    }
                }

                Picker("Model", selection: $selectedModel) {
                    Text("Default").tag("")
                    if let agent = selectedAgent {
                        ForEach(agent.models, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                }
                .disabled(selectedProvider.isEmpty)
            }

            Section {
                // A chosen folder is a URI (`file://<machine>/path`) too long to
                // read in a one-line field; say it plainly above the field.
                if let uri = trimmedDirectory, uri.hasPrefix("file:") || uri.hasPrefix("\(FolderURI.brokerScheme):") {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(FolderURI.name(uri), systemImage: "folder.fill")
                            .font(.body.weight(.semibold))
                        Text(FolderURI.path(uri))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.head)
                        if let machine = FolderURI.machine(uri) {
                            Text("on \(machine)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                TextField("e.g. /Users/me/project", text: $workingDirectory)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: workingDirectory) { _, _ in directoryWasAutofilled = false }

                if !recentFolders.isEmpty || !store.pinnedFolders.isEmpty {
                    Menu {
                        if !store.pinnedFolders.isEmpty {
                            Section("Pinned") { folderButtons(store.pinnedFolders) }
                        }
                        if !recentFolders.isEmpty {
                            Section("Recent") { folderButtons(recentFolders) }
                        }
                    } label: {
                        Label(
                            store.pinnedFolders.isEmpty ? "Recent folders" : "Pinned & recent folders",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                }

                Button {
                    showingBrowser = true
                } label: {
                    Label("Browse…", systemImage: "folder")
                }
                .disabled(browseStart == nil)
            } header: {
                Text("Working Directory")
            } footer: {
                if let dir = usableDefaultDirectory {
                    // Through a broker the default is a machine's root, whose
                    // path alone reads "/".
                    let machine = FolderURI.machine(dir).map { " on \($0)" } ?? ""
                    Text("Server default: \(FolderURI.path(dir))\(machine)")
                } else if browseStart == nil, !selectedProvider.isEmpty {
                    Text("This host doesn't say where its folders are. Type a path; after the first chat, its folder is offered here.")
                }
            }

            if let configSchema {
                SessionConfigSection(schema: configSchema, values: configValues) { key, value in
                    configValues[key] = value
                    // The answer is the full property set for these values, and
                    // one choice can change what else is offered.
                    Task { await resolveConfig() }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    onSelect(
                        selectedProvider,
                        selectedModel.isEmpty ? nil : selectedModel,
                        trimmedDirectory,
                        configSchema == nil ? [:] : configValues
                    )
                }
                .disabled(!canCreate)
            }
        }
        .onAppear {
            if let dir = initialDirectory {
                workingDirectory = dir
            } else if let dir = usableDefaultDirectory, workingDirectory.isEmpty {
                setDirectory(dir, autofilled: true)
            }
            if store.agents.count == 1, let agent = store.agents.first {
                selectedProvider = agent.provider
            }
        }
        .sheet(isPresented: $showingBrowser) {
            if let start = browseStart {
                // The browser owns its navigation stack (push, swipe back).
                FolderBrowserView(start: start) { setDirectory($0, autofilled: false) }
                    .environment(store)
            }
        }
        .onChange(of: selectedProvider) {
            selectedModel = ""
            if trimmedDirectory == nil || directoryWasAutofilled,
               let folder = recentFolders.first ?? usableDefaultDirectory {
                setDirectory(folder, autofilled: true)
            }
            // Another agent's settings are not this one's.
            configSchema = nil
            configValues = [:]
        }
        // Re-ask when the agent or folder changes; the pause keeps typing a
        // path from sending a request per keystroke.
        .task(id: "\(selectedProvider)\u{0}\(workingDirectory)") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await resolveConfig()
        }
    }

    private func folderButtons(_ folders: [String]) -> some View {
        ForEach(folders, id: \.self) { uri in
            Button {
                setDirectory(uri, autofilled: false)
            } label: {
                Text(FolderURI.name(uri))
                Text([FolderURI.path(uri), FolderURI.machine(uri).map { "on \($0)" }]
                    .compactMap { $0 }.joined(separator: " "))
            }
        }
    }

    private func setDirectory(_ uri: String, autofilled: Bool) {
        workingDirectory = uri
        // Set after the field's own onChange has cleared it.
        DispatchQueue.main.async { directoryWasAutofilled = autofilled }
    }

    private func resolveConfig() async {
        guard !selectedProvider.isEmpty else { return }
        resolveGeneration += 1
        let generation = resolveGeneration
        let result = await store.resolveSessionConfig(
            provider: selectedProvider,
            workingDirectory: trimmedDirectory,
            values: configValues
        )
        guard generation == resolveGeneration else { return }
        guard let result, !result.schema.properties.isEmpty else {
            configSchema = nil
            configValues = [:]
            return
        }
        configSchema = result.schema
        configValues = result.values
    }
}
