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
                TextField("e.g. /Users/me/project", text: $workingDirectory)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: {
                Text("Working Directory")
            } footer: {
                if let dir = store.defaultDirectory {
                    let display = dir.hasPrefix("file://") ? String(dir.dropFirst(7)) : dir
                    Text("Server default: \(display)")
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
            } else if let dir = store.defaultDirectory, workingDirectory.isEmpty {
                workingDirectory = dir
            }
            if store.agents.count == 1, let agent = store.agents.first {
                selectedProvider = agent.provider
            }
        }
        .onChange(of: selectedProvider) {
            selectedModel = ""
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
