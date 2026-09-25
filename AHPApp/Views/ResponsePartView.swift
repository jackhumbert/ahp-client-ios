import AgentHostProtocol
import SwiftUI
import UIKit

private func toolInputText(_ input: ToolInput?) -> String? {
    switch input {
    case .inline(let value): return value
    case .contentRef(let ref): return ref.uri
    case nil: return nil
    }
}

/// Renders a single response part: markdown text, reasoning, tool call, or content ref.
struct ResponsePartView: View {
    let part: ResponsePart

    var body: some View {
        switch part {
        case .markdown(let md):
            MarkdownPartView(part: md)
        case .reasoning(let r):
            ReasoningPartView(part: r)
        case .toolCall(let tc):
            ToolCallPartView(toolCall: tc.toolCall)
        case .contentRef(let ref):
            ContentRefView(ref: ref)
        case .systemNotification(let note):
            SystemNotificationPartView(part: note)
        case .error(let error):
            ErrorResponsePartView(part: error)
        case .inputRequest, .unknown:
            EmptyView()
        }
    }
}

// MARK: - ErrorResponsePartView

struct ErrorResponsePartView: View {
    let part: ErrorResponsePart

    var body: some View {
        Label(part.error.message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.1), in: Capsule())
    }
}

// MARK: - SystemNotificationPartView

struct SystemNotificationPartView: View {
    let part: SystemNotificationResponsePart

    private var text: String {
        switch part.content {
        case .string(let s): return s
        case .markdown(let m): return m
        }
    }

    /// A message the user steered into the turn (`_meta.steering`, set by
    /// agent-host-server): drawn as theirs, where it joined.
    private var isSteering: Bool {
        (part.meta?["steering"]?.value as? Bool) == true
    }

    var body: some View {
        if isSteering {
            VStack(alignment: .trailing, spacing: 4) {
                UserBubble(text: text, attachments: nil)
                Label("Joined this turn", systemImage: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
        } else {
            notice
        }
    }

    private var notice: some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

// MARK: - MarkdownPartView

struct MarkdownPartView: View {
    let part: MarkdownResponsePart

    var body: some View {
        let content = part.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            MarkdownBlocksView(content)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
    }
}

// MARK: - ReasoningPartView

struct ReasoningPartView: View {
    let part: ReasoningResponsePart
    @State private var isExpanded = false

    /// Drawn like a compact tool row - icon on the reply text's left edge,
    /// the same neutral grey card - so thinking reads as part of the agent's
    /// work rather than a purple banner.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text("Thinking")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.leading, 4)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Text(part.content)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Under the label, and the same space below as above.
                    .padding(.leading, 30)
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isExpanded ? Color(.secondarySystemBackground) : .clear)
        )
    }
}

// MARK: - ToolCallPartView

struct ToolCallPartView: View {
    let toolCall: ToolCallState
    /// One line regardless of the setting (inside a collapsed group).
    var forceCompact = false
    @Environment(AppStore.self) private var store
    @AppStorage(ToolCallStyle.storageKey) private var style: ToolCallStyle = .cards
    @State private var showDetail = false
    @State private var showInputRequest = false

    /// One line, unless the call is waiting on the user: that always gets
    /// the full card with its buttons.
    private var isCompact: Bool {
        (forceCompact || style != .cards) && !toolCall.needsUser && pendingInputRequest == nil
    }

    var body: some View {
        if isCompact {
            compactRow
        } else {
            card
        }
    }

    private var compactRow: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: toolIcon)
                    .font(.footnote)
                    .foregroundStyle(toolColor)
                    .frame(width: 18)
                Text(compactLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                statusView
                    .font(.footnote)
            }
            // Icons on the same left edge as reply text (4pt in).
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(compactLine)
        .sheet(isPresented: $showDetail) {
            ToolCallDetailSheet(toolCall: toolCall)
        }
    }

    /// What the call did, in a line: its own message or description, else
    /// the tool's name and what it touched ("Read file · /repo/README.md").
    private var compactLine: String {
        if let line = invocationLine { return line }
        if let summary = toolInputSummary { return "\(displayName) · \(summary)" }
        return displayName
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            details
                // Only the details open the sheet: a tap gesture on the whole
                // card took the buttons' taps, so Approve opened the sheet.
                .contentShape(Rectangle())
                .onTapGesture {
                    if pendingInputRequest != nil {
                        showInputRequest = true
                    } else {
                        showDetail = true
                    }
                }

            // Action buttons
            actionButtons
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .onChange(of: store.currentInputRequests.map(\.id)) { _, ids in
            // Auto-dismiss the input sheet if the request was resolved.
            if showInputRequest, let req = pendingInputRequest, !ids.contains(req.id) {
                showInputRequest = false
            }
        }
        .sheet(isPresented: $showDetail) {
            ToolCallDetailSheet(toolCall: toolCall)
        }
        .sheet(isPresented: $showInputRequest) {
            if let req = pendingInputRequest {
                InputRequestSheet(request: req) { showInputRequest = false }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: toolIcon)
                    .foregroundStyle(toolColor)
                Text(displayName)
                    .font(.subheadline.bold())
                Spacer()
                statusView
            }

            // Tool invocation message. Hosts often use the command itself as
            // the message (opencode, the Windows Claude node); then the call's
            // own `description` says more, and without one the line would only
            // repeat the command shown below it.
            if let line = invocationLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // What it actually ran or touched. Hosts' invocation messages can
            // be generic ("Running Run command"), while the arguments say
            // exactly what happened.
            if let summary = toolInputSummary {
                Text(summary)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary.opacity(0.8))
                    .textSelection(.enabled)
            }

            if let title = confirmationTitle {
                Label(stringOrMarkdownText(title), systemImage: "lock.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            if let selectedOption {
                Label(selectedOption.label, systemImage: selectedOption.kind == .approve ? "checkmark.shield" : "xmark.shield")
                    .font(.caption)
                    .foregroundStyle(selectedOption.kind == .approve ? .green : .secondary)
            }

            // Show a failure label for completed-but-failed calls
            if case .completed(let s) = toolCall, !s.success {
                Label("Tool failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Show cancellation reason
            if case .cancelled(let s) = toolCall, let reason = s.reasonMessage {
                Text(stringOrMarkdownText(reason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        switch toolCall {
        case .streaming:
            ProgressView().controlSize(.mini)
        case .pendingConfirmation:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        case .running:
            ProgressView().controlSize(.mini)
        case .authRequired:
            Image(systemName: "lock.circle.fill")
                .foregroundStyle(.orange)
        case .pendingResultConfirmation:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        case .completed(let s):
            Image(systemName: s.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(s.success ? .green : .red)
        case .cancelled:
            Image(systemName: "slash.circle.fill")
                .foregroundStyle(.secondary)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        // When the tool is awaiting user input via an open input request,
        // surface a single "Respond" CTA. The request is opened on tap.
        if pendingInputRequest != nil {
            Button {
                showInputRequest = true
            } label: {
                Label("Respond", systemImage: "arrow.up.message")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
        } else {
            confirmationActionButtons
        }
    }

    @ViewBuilder
    private var confirmationActionButtons: some View {
        switch toolCall {
        case .pendingConfirmation(let pending):
            confirmationButtonStack(options: pending.options ?? [])
        case .pendingResultConfirmation:
            decisionRow(
                deny: DecisionButton(label: "Reject") {
                    // Result denial not exposed yet
                },
                approve: DecisionButton(label: "Accept") {
                    if let ids = turnAndToolId {
                        Task { await store.approveToolCallResult(toolCallId: ids.toolCallId, turnId: ids.turnId) }
                    }
                }
            )
        default:
            EmptyView()
        }
    }

    /// Deny on the left, approve on the right, side by side and equally large:
    /// stacked one above the other, a thumb aimed at one lands on the other.
    /// Options beyond the first of each kind ("Allow for this session", …)
    /// sit above the row as full-width buttons.
    @ViewBuilder
    private func confirmationButtonStack(options: [ConfirmationOption]) -> some View {
        let approveOptions = options.filter { $0.kind == .approve }
        let denyOptions = options.filter { $0.kind == .deny }

        VStack(spacing: 8) {
            ForEach(approveOptions.dropFirst(), id: \.id) { option in
                Button { submit(option) } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 10))
            }
            ForEach(denyOptions.dropFirst(), id: \.id) { option in
                Button(role: .destructive) { submit(option) } label: {
                    Text(option.label)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 10))
            }

            decisionRow(
                deny: denyOptions.first.map { option in
                    DecisionButton(label: option.label) { submit(option) }
                } ?? DecisionButton(label: "Deny") {
                    if let ids = turnAndToolId {
                        Task { await store.denyToolCall(toolCallId: ids.toolCallId, turnId: ids.turnId) }
                    }
                },
                approve: approveOptions.first.map { option in
                    DecisionButton(label: option.label) { submit(option) }
                } ?? DecisionButton(label: "Approve") {
                    if let ids = turnAndToolId {
                        Task { await store.approveToolCall(toolCallId: ids.toolCallId, turnId: ids.turnId) }
                    }
                }
            )
        }
    }

    private struct DecisionButton {
        let label: String
        let action: () -> Void
    }

    private func decisionRow(deny: DecisionButton, approve: DecisionButton) -> some View {
        HStack(spacing: 12) {
            Button(role: .destructive, action: deny.action) {
                Text(deny.label)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: approve.action) {
                Text(approve.label)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 10))
    }

    private func submit(_ option: ConfirmationOption) {
        guard let ids = turnAndToolId else { return }
        Task {
            switch option.kind {
            case .approve:
                await store.approveToolCall(
                    toolCallId: ids.toolCallId,
                    turnId: ids.turnId,
                    selectedOptionId: option.id
                )
            case .deny:
                await store.denyToolCall(
                    toolCallId: ids.toolCallId,
                    turnId: ids.turnId,
                    selectedOptionId: option.id
                )
            case .unknown:
                // An option kind from a newer host: we cannot tell whether it
                // approves, so send nothing rather than guess.
                break
            }
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        toolCall.baseFields.displayName
    }

    private var toolIcon: String {
        // Lowercased: Claude Code's tools are `Bash`, `Read`, `Edit`, ….
        let name = toolCall.baseFields.toolName.lowercased()
        switch name {
        case "bash", "terminal", "runcommand": return "terminal"
        case "readfile", "read_file", "read", "notebookread": return "doc.text"
        case "writefile", "write_file", "editfile", "edit_file", "write", "edit", "multiedit", "notebookedit":
            return "doc.badge.plus"
        case "listdirectory", "list_directory", "ls", "glob": return "folder"
        case "grep": return "magnifyingglass"
        case "webfetch", "websearch": return "globe"
        default: return "wrench"
        }
    }

    private var toolColor: Color {
        switch toolCall {
        case .pendingConfirmation, .pendingResultConfirmation, .authRequired: .orange
        case .running, .streaming: .blue
        case .completed(let s): s.success ? .secondary : .red
        case .cancelled: .secondary
        case .unknown: .secondary
        }
    }

    private var cardBackground: Color {
        switch toolCall {
        case .pendingConfirmation, .pendingResultConfirmation:
            return Color.orange.opacity(0.05)
        case .completed(let s) where !s.success:
            return Color.red.opacity(0.04)
        default:
            return Color(.systemGray6).opacity(0.5)
        }
    }

    private var borderColor: Color {
        switch toolCall {
        case .pendingConfirmation, .pendingResultConfirmation: .orange.opacity(0.4)
        case .completed(let s): s.success ? Color(.systemGray4).opacity(0.5) : .red.opacity(0.3)
        default: Color(.systemGray4).opacity(0.5)
        }
    }

    private var invocationMessage: StringOrMarkdown? {
        switch toolCall {
        case .streaming(let s): return s.invocationMessage
        case .pendingConfirmation(let s): return s.invocationMessage
        case .running(let s): return s.invocationMessage
        case .pendingResultConfirmation(let s): return s.invocationMessage
        case .completed(let s): return s.invocationMessage
        case .authRequired(let s): return s.invocationMessage
        case .cancelled(let s): return s.invocationMessage
        case .unknown: return nil
        }
    }

    private var invocationLine: String? {
        guard let msg = invocationMessage else { return toolInputDescription }
        let text = stringOrMarkdownText(msg)
        // agent-host-server's stand-in when an agent sends no message says
        // nothing the tool's name doesn't.
        if text == "Running \(displayName)" { return toolInputDescription }
        guard ToolCallText.repeats(text, summary: toolInputSummary, displayName: displayName) else {
            return text
        }
        return toolInputDescription
    }

    /// The `description` an agent gives a call (Claude Code's and opencode's
    /// shell tools both take one), from an inline JSON-object input.
    private var toolInputDescription: String? {
        guard let text = toolInput, text.hasPrefix("{"),
              let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let description = (object["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return description
    }

    /// The one argument that says what a call did, from an inline JSON-object
    /// input: a shell command, else a path, pattern, URL or query. The keys are
    /// the ones Claude Code's and VS Code's tools use; any other input shape
    /// shows nothing here and stays available in the detail sheet.
    private var toolInputSummary: String? {
        guard let text = toolInput,
              text.hasPrefix("{"),
              let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if let command = object["command"] as? String, !command.isEmpty {
            return "$ " + command
        }
        for key in ["file_path", "notebook_path", "pattern", "url", "query", "path"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private var toolInput: String? {
        switch toolCall {
        case .pendingConfirmation(let s): return toolInputText(s.toolInput)
        case .running(let s): return toolInputText(s.toolInput)
        case .pendingResultConfirmation(let s): return toolInputText(s.toolInput)
        case .completed(let s): return toolInputText(s.toolInput)
        case .cancelled(let s): return toolInputText(s.toolInput)
        default: return nil
        }
    }

    private var confirmationTitle: StringOrMarkdown? {
        guard case .pendingConfirmation(let pending) = toolCall else { return nil }
        return pending.confirmationTitle
    }

    private var selectedOption: ConfirmationOption? {
        switch toolCall {
        case .running(let state):
            return state.selectedOption
        case .pendingResultConfirmation(let state):
            return state.selectedOption
        case .completed(let state):
            return state.selectedOption
        case .cancelled(let state):
            return state.selectedOption
        default:
            return nil
        }
    }

    /// Get turnId + toolCallId for dispatching actions.
    /// The turnId comes from the current active turn in the store.
    private var turnAndToolId: (turnId: String, toolCallId: String)? {
        let tcId = toolCall.toolCallId
        if let activeTurn = store.currentChat?.activeTurn {
            return (activeTurn.id, tcId)
        }
        return nil
    }

    /// The session's first open input request, if this tool call is the
    /// likely target. The protocol does not currently link a request to a
    /// specific tool call, so we attribute it to the latest streaming/running
    /// tool call in the active turn (assumed to be `self`).
    private var pendingInputRequest: ChatInputRequest? {
        let requests = store.currentInputRequests
        guard !requests.isEmpty else {
            return nil
        }
        // Only attach to streaming/running tools — pendingConfirmation /
        // pendingResultConfirmation have their own UI flow.
        switch toolCall {
        case .streaming, .running: break
        default: return nil
        }
        // If multiple in-progress tool calls exist in the active turn, only
        // the most recent one owns the prompt to avoid showing duplicate CTAs.
        let activeParts = store.currentChat?.activeTurn?.responseParts ?? []
        let lastRunningId: String? = activeParts.reversed().compactMap { part -> String? in
            guard case .toolCall(let tc) = part else { return nil }
            switch tc.toolCall {
            case .streaming, .running: return tc.toolCall.toolCallId
            default: return nil
            }
        }.first
        guard lastRunningId == toolCall.toolCallId else { return nil }
        return requests.first
    }

    private func stringOrMarkdownText(_ value: StringOrMarkdown) -> String {
        switch value {
        case .string(let s): return s
        case .markdown(let m): return m
        }
    }
}

// MARK: - ToolCallDetailSheet

/// Modal sheet showing the full input (parameters) and output (result content) of a tool call.
struct ToolCallDetailSheet: View {
    let toolCall: ToolCallState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // --- Input Section ---
                    if let input = toolInput, !input.isEmpty {
                        Section {
                            Text(input)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                        } header: {
                            Label("Input", systemImage: "arrow.right.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    // --- Output Section ---
                    if let content = toolResultContent, !content.isEmpty {
                        Section {
                            ForEach(Array(content.enumerated()), id: \.offset) { _, item in
                                ToolResultContentView(content: item)
                            }
                        } header: {
                            Label("Output", systemImage: "arrow.left.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                    } else if hasResult {
                        Section {
                            Text("No output content")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } header: {
                            Label("Output", systemImage: "arrow.left.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(toolCall.baseFields.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var toolInput: String? {
        switch toolCall {
        case .pendingConfirmation(let s): return toolInputText(s.toolInput)
        case .running(let s): return toolInputText(s.toolInput)
        case .pendingResultConfirmation(let s): return toolInputText(s.toolInput)
        case .completed(let s): return toolInputText(s.toolInput)
        case .cancelled(let s): return toolInputText(s.toolInput)
        default: return nil
        }
    }

    private var toolResultContent: [ToolResultContent]? {
        switch toolCall {
        case .completed(let s): return s.content
        case .pendingResultConfirmation(let s): return s.content
        default: return nil
        }
    }

    private var hasResult: Bool {
        switch toolCall {
        case .completed, .pendingResultConfirmation: return true
        default: return false
        }
    }
}

// MARK: - ToolResultContentView

struct ToolResultContentView: View {
    let content: ToolResultContent

    var body: some View {
        switch content {
        case .text(let t):
            Text(t.text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
        case .embeddedResource(let b):
            if b.contentType.hasPrefix("image/") == true,
               let data = Data(base64Encoded: b.data),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label("Binary content (\(b.contentType))", systemImage: "doc.zipper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .resource(let r):
            Label(r.uri, systemImage: "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .fileEdit(let edit):
            HStack {
                Image(systemName: "doc.badge.gearshape")
                VStack(alignment: .leading) {
                    Text("File edit")
                        .font(.caption.bold())
                    if let diff = edit.diff?.value as? [String: Any] {
                        HStack(spacing: 4) {
                            Text("+\(diff["added"] as? Int ?? 0)")
                                .foregroundStyle(.green)
                            Text("-\(diff["removed"] as? Int ?? 0)")
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
        case .terminal(let t):
            TerminalToolResultView(ref: t)
        case .subagent(let s):
            Label(s.resource, systemImage: "person.2")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unknown:
            Label("Result this app can't display", systemImage: "questionmark.square.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - TerminalToolResultView

/// Renders the live state of a terminal referenced by a tool result using
/// SwiftTerm for proper VT100 rendering. Subscribes to the terminal URI
/// on appearance and streams its content into the native terminal emulator.
struct TerminalToolResultView: View {
    let ref: ToolResultTerminalContent
    @Environment(AppStore.self) private var store

    private var state: TerminalState? {
        store.terminals[ref.resource]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(ref.title, systemImage: "terminal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let state {
                if state.content.isEmpty && !state.hasExited {
                    Text("(waiting for output…)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if state.content.isEmpty {
                    Text("(no output)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    AHPTerminalSwiftUIView(terminalURI: ref.resource)
                        .frame(height: terminalHeight(for: state))
                }
                if let code = state.exitCode {
                    Text("Exited with code \(code)")
                        .font(.caption2)
                        .foregroundStyle(code == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        .task(id: ref.resource) {
            await store.ensureTerminalSubscribed(uri: ref.resource)
        }
    }

    /// Compute a reasonable height for the terminal view based on content.
    private func terminalHeight(for state: TerminalState) -> CGFloat {
        let rows = state.rows ?? 24
        // 13pt monospaced font → ~17pt cell height (ascent + descent + leading).
        let cellHeight: CGFloat = 17
        let height = CGFloat(min(rows, 40)) * cellHeight
        return max(200, min(height, 680))
    }
}

// MARK: - ContentRefView

struct ContentRefView: View {
    let ref: ResourceResponsePart

    var body: some View {
        HStack {
            Image(systemName: contentIcon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(ref.uri)
                    .font(.caption)
                    .lineLimit(1)
                if let type = ref.contentType {
                    Text(type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.systemGray4).opacity(0.5), lineWidth: 1)
        )
    }

    private var contentIcon: String {
        if ref.contentType?.hasPrefix("image/") == true { return "photo" }
        if ref.contentType?.hasPrefix("text/") == true { return "doc.text" }
        return "doc"
    }
}

// MARK: - Previews

#Preview("All Response Parts", traits: .fixedLayout(width: 390, height: 2200)) {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            // Markdown
            Text("Markdown").font(.caption.bold()).foregroundStyle(.secondary)
            MarkdownPartView(part: MarkdownResponsePart(
                kind: .markdown,
                id: "p1",
                content: """
                Here is some **bold** text and `inline code`.

                - First item
                - Second item

                ```swift
                let x = 42
                ```
                """
            ))

            // Reasoning
            Text("Reasoning").font(.caption.bold()).foregroundStyle(.secondary)
            ReasoningPartView(part: ReasoningResponsePart(
                kind: .reasoning,
                id: "r1",
                content: "Let me think about this step by step. The user wants to refactor the authentication module to use JWT tokens instead of session cookies."
            ))

            // Tool Call — Streaming
            Text("Tool Call — Streaming").font(.caption.bold()).foregroundStyle(.secondary)
            ToolCallPartView(toolCall: .streaming(ToolCallStreamingState(
                toolCallId: "tc0",
                toolName: "editFile",
                displayName: "Edit file",
                status: .streaming,
                invocationMessage: .string("Editing src/main.ts")
            )))

            // Tool Call — Pending Confirmation
            Text("Tool Call — Pending Confirmation").font(.caption.bold()).foregroundStyle(.secondary)
            ToolCallPartView(toolCall: .pendingConfirmation(ToolCallPendingConfirmationState(
                toolCallId: "tc0b",
                toolName: "bash",
                displayName: "Run command",
                invocationMessage: .string("Run: npm run deploy"),
                toolInput: .inline("{\"command\": \"npm run deploy\"}"),
                status: .pendingConfirmation,
                confirmationTitle: .string("Allow deployment?")
            )))

            // Tool Call — Running
            Text("Tool Call — Running").font(.caption.bold()).foregroundStyle(.secondary)
            ToolCallPartView(toolCall: .running(ToolCallRunningState(
                toolCallId: "tc1",
                toolName: "bash",
                displayName: "Run command",
                invocationMessage: .string("Running: npm test"),
                toolInput: .inline("{\"command\": \"npm test\"}"),
                confirmed: .notNeeded,
                status: .running
            )))

            // Tool Call — Completed
            Text("Tool Call — Completed").font(.caption.bold()).foregroundStyle(.secondary)
            ToolCallPartView(toolCall: .completed(ToolCallCompletedState(
                toolCallId: "tc2",
                toolName: "readFile",
                displayName: "Read file",
                invocationMessage: .string("Reading package.json"),
                toolInput: .contentRef(ContentRef(uri: "file:///tool-inputs/tc2.json")),
                success: true,
                pastTenseMessage: .string("Read package.json"),
                content: [.text(ToolResultTextContent(type: .text, text: "{\"name\": \"my-app\"}"))],
                confirmed: .notNeeded,
                status: .completed
            )))

            // Tool Call — Failed
            Text("Tool Call — Failed").font(.caption.bold()).foregroundStyle(.secondary)
            ToolCallPartView(toolCall: .completed(ToolCallCompletedState(
                toolCallId: "tc3",
                toolName: "bash",
                displayName: "Run command",
                invocationMessage: .string("Running: rm -rf /"),
                toolInput: .inline("{\"command\": \"rm -rf /\"}"),
                success: false,
                pastTenseMessage: .string("Command failed"),
                confirmed: .userAction,
                status: .completed
            )))

            // Tool Call — Pending Result Confirmation
            Text("Tool Call — Pending Result").font(.caption.bold()).foregroundStyle(.secondary)
            ToolCallPartView(toolCall: .pendingResultConfirmation(ToolCallPendingResultConfirmationState(
                toolCallId: "tc4",
                toolName: "writeFile",
                displayName: "Write file",
                invocationMessage: .string("Writing config.json"),
                toolInput: .contentRef(ContentRef(uri: "file:///tool-inputs/tc4.json")),
                success: true,
                pastTenseMessage: .string("Wrote config.json"),
                content: [.text(ToolResultTextContent(type: .text, text: "File written successfully"))],
                confirmed: .userAction,
                status: .pendingResultConfirmation
            )))

            // Tool Call — Cancelled
            Text("Tool Call — Cancelled").font(.caption.bold()).foregroundStyle(.secondary)
            ToolCallPartView(toolCall: .cancelled(ToolCallCancelledState(
                toolCallId: "tc5",
                toolName: "bash",
                displayName: "Run command",
                invocationMessage: .string("Running: git push --force"),
                toolInput: .inline("{\"command\": \"git push --force\"}"),
                status: .cancelled,
                reason: .denied,
                reasonMessage: .string("User denied force push")
            )))

            // Content Ref
            Text("Content Ref").font(.caption.bold()).foregroundStyle(.secondary)
            ContentRefView(ref: ResourceResponsePart(
                uri: "file:///Users/me/project/README.md",
                contentType: "text/markdown",
                kind: .contentRef
            ))
        }
        .padding()
    }
    .environment(AppStore())
}

/// Text rules for tool-call cards.
enum ToolCallText {
    /// True when a host's one-line message says nothing the input summary
    /// (`$ command`, a path, …) doesn't: the same text, maybe truncated with
    /// "…", maybe after the tool's display name ("Run command: ls").
    static func repeats(_ message: String, summary: String?, displayName: String) -> Bool {
        guard let summary else { return false }
        var message = normalized(message)
        let prefix = normalized(displayName) + ":"
        if message.hasPrefix(prefix) {
            message = String(message.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        var shown = normalized(summary)
        if shown.hasPrefix("$ ") { shown = String(shown.dropFirst(2)) }
        guard !message.isEmpty, !shown.isEmpty else { return false }
        return shown.hasPrefix(message) || message.hasPrefix(shown)
    }

    /// Whitespace collapsed and a trailing ellipsis dropped: hosts shorten
    /// their messages, and the card shortens the summary.
    private static func normalized(_ text: String) -> String {
        var text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for ellipsis in ["…", "..."] where text.hasSuffix(ellipsis) {
            text = String(text.dropLast(ellipsis.count)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}
