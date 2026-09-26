import AgentHostProtocol
import SwiftUI
import UIKit

/// Main chat view showing the conversation with the agent.
struct ChatView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("showSessionDebugStatus") private var showSessionDebugStatus = false
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    /// Tracks whether the scroll position is at (or near) the bottom.
    @State private var isAtBottom = true
    /// URI of an interactive terminal to navigate to.
    @State private var activeTerminalURI: String?
    @State private var browsingFiles = false
    /// A file a link in a reply points at, open in a sheet.
    @State private var openedFile: FileLink?
    /// Currently presented input request in the modal sheet.
    @State private var presentedInputRequestId: String?

    // MARK: - Scroll helpers

    /// The stable ID of the bottom-sentinel view used as the scroll target.
    private let bottomID = "chat-bottom-sentinel"
    private var sessionPermissionPickerModel: SessionPermissionPickerModel? {
        guard let session = store.currentSession else { return nil }
        return SessionPermissionPickerModel(session: session)
    }
    private var sessionModelPickerModel: SessionModelPickerModel? {
        guard let session = store.currentSession else { return nil }
        let selectedModelId = store.selectedSessionURI.flatMap { store.selectedModelId(for: $0) }
        return SessionModelPickerModel(session: session, agents: store.agents, selectedModelId: selectedModelId)
    }

    /// True when the active turn has at least one streaming or running tool
    /// call. Used to suppress the floating input-request prompt because the
    /// owning tool card already shows its own "Respond" CTA.
    private var hasInProgressToolCall: Bool {
        guard let parts = store.currentChat?.activeTurn?.responseParts else { return false }
        for part in parts {
            if case .toolCall(let tc) = part {
                switch tc.toolCall {
                case .streaming, .running: return true
                default: continue
                }
            }
        }
        return false
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if store.currentSessionRequiresAuth {
                            AuthRequiredPanel(session: store.currentSession)
                                .padding(.top, 24)
                        }

                        if let chat = store.currentChat {
                            // Completed turns
                            ForEach(chat.turns, id: \.id) { turn in
                                TurnView(turn: turn, activeTurnId: nil)
                                    .id(turn.id)
                            }

                            // Active turn (streaming)
                            if let activeTurn = chat.activeTurn {
                                ActiveTurnView(turn: activeTurn)
                                    .id("active-\(activeTurn.id)")
                            }

                            // Steering message — will be injected into the
                            // current turn at the server's next opportunity.
                            if let steering = chat.steeringMessage {
                                PendingMessageView(
                                    message: steering,
                                    caption: "Next — joins this turn",
                                    captionIcon: "arrow.turn.down.right",
                                    onRemove: { Task { await store.removePendingMessage(kind: .steering, id: steering.id) } }
                                )
                                .id("steering-\(steering.id)")
                            }

                            // Queued messages — auto-started as new turns
                            // after the current turn completes (or immediately
                            // when the session is idle).
                            if let queued = chat.queuedMessages {
                                ForEach(queued, id: \.id) { msg in
                                    PendingMessageView(
                                        message: msg,
                                        caption: "Later — after this turn",
                                        captionIcon: "clock",
                                        onRemove: { Task { await store.removePendingMessage(kind: .queued, id: msg.id) } }
                                    )
                                    .id("queued-\(msg.id)")
                                }
                            }
                        }

                        // Bottom sentinel — scroll target and at-bottom detection.
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                            .onAppear  { isAtBottom = true }
                            .onDisappear { isAtBottom = false }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    isAtBottom = true
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: store.selectedSessionURI) {
                    isAtBottom = true
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: store.currentChat?.activeTurn?.responseParts.count) {
                    if isAtBottom {
                        scrollToBottom(proxy, animated: true)
                    }
                }
                .onChange(of: store.currentChat?.turns.count) {
                    if isAtBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToBottom(proxy, animated: true)
                        }
                    }
                }
                .onChange(of: store.currentChat?.queuedMessages?.count) {
                    if isAtBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToBottom(proxy, animated: true)
                        }
                    }
                }
                .onChange(of: store.currentChat?.steeringMessage?.id) {
                    if isAtBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToBottom(proxy, animated: true)
                        }
                    }
                }

                // Scroll-to-bottom button — visible when the user has scrolled up.
                if !isAtBottom {
                    Button {
                        scrollToBottom(proxy, animated: true)
                    } label: {
                        if #available(iOS 26, *) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: .circle)
                        } else {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .accessibilityLabel("Scroll to bottom")
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeOut(duration: 0.15), value: isAtBottom)
                }
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if store.isCurrentSessionStale || store.isCurrentSessionSyncing {
                        SessionSyncStatusBar(isSyncing: store.isCurrentSessionSyncing)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Floating reconnect progress bar
                    if store.isReconnectBannerVisible {
                        ReconnectProgressBar(
                            stage: store.connectionStage,
                            serverName: store.selectedServer?.name
                        )
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 8)
            }
            .animation(.easeInOut(duration: 0.2), value: store.isReconnectBannerVisible)
            .animation(.easeInOut(duration: 0.25), value: store.isCurrentSessionStale)
            .animation(.easeInOut(duration: 0.25), value: store.isCurrentSessionSyncing)
            // InputBar is declared as a safe-area inset so the scroll view
            // shrinks its visible frame to end above the bar. This ensures
            // scrollToBottom lands at the true visible bottom, not behind the bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    // Pending input requests (elicitation) — shown only when
                    // no in-progress tool call owns the request. The active
                    // tool card embeds its own "Respond" CTA in that case.
                    let requests = store.currentInputRequests
                    if !requests.isEmpty,
                       !hasInProgressToolCall {
                        VStack(spacing: 8) {
                            ForEach(requests, id: \.id) { request in
                                InputRequestPrompt(request: request) {
                                    presentedInputRequestId = request.id
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }


                    if showSessionDebugStatus {
                        SessionDebugStatusBar(
                            connectionState: store.connectionState,
                            isSessionSyncing: store.isCurrentSessionSyncing,
                            isSessionStale: store.isCurrentSessionStale,
                            selectedSessionURI: store.selectedSessionURI,
                            status: store.sessionDebugStatus
                        )
                    }

                    InputBar(
                        text: $inputText,
                        isFocused: $inputFocused,
                        modelPicker: SessionInlineAccessories(
                            permissionModel: sessionPermissionPickerModel,
                            modelPickerModel: sessionModelPickerModel
                        )
                    ) { delivery in
                        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let message = inputText
                        inputText = ""
                        Task { await store.sendMessage(message, delivery: delivery) }
                    }
                }
            }
        }
        .navigationTitle(chatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A smaller title than the navigation bar's own: chat titles are
            // the first message, and long.
            ToolbarItem(placement: .principal) {
                Text(chatTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if store.currentWorkingDirectory != nil {
                        Button("Browse Files", systemImage: "folder") {
                            browsingFiles = true
                        }
                        .disabled(store.connectionState != .connected)
                    }
                    Button("New Terminal", systemImage: "terminal") {
                        Task {
                            if let uri = await store.createTerminal() {
                                activeTerminalURI = uri
                            }
                        }
                    }
                    .disabled(store.connectionState != .connected)
                    Button("Reconnect", systemImage: "arrow.trianglehead.2.clockwise") {
                        Task { await store.reconnect() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("Chat actions")
                }
            }
        }
        .navigationDestination(item: $activeTerminalURI) { uri in
            InteractiveTerminalView(terminalURI: uri)
        }
        // Links in replies: web links open in the browser, anything naming a
        // file resolves against the session's folder and opens here.
        .environment(\.openURL, OpenURLAction { url in
            guard let link = FileLink.resolve(url.absoluteString, base: store.currentWorkingDirectory) else {
                return .systemAction
            }
            openedFile = link
            return .handled
        })
        .sheet(isPresented: $browsingFiles) {
            if let folder = store.currentWorkingDirectory {
                FolderBrowserView(start: folder)
                    .environment(store)
            }
        }
        .sheet(item: $openedFile) { link in
            NavigationStack {
                FileViewerView(link: link)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { openedFile = nil }
                        }
                    }
            }
            .environment(store)
        }
        .sheet(item: Binding(
            get: { presentedInputRequest.map { IdentifiedRequest(request: $0) } },
            set: { presentedInputRequestId = $0?.request.id }
        )) { wrapper in
            InputRequestSheet(request: wrapper.request) {
                presentedInputRequestId = nil
            }
        }
        .onChange(of: store.currentInputRequests.map(\.id)) { _, ids in
            // Auto-dismiss the sheet if the active request was resolved.
            if let id = presentedInputRequestId, !ids.contains(id) {
                presentedInputRequestId = nil
            }
        }
    }

    private var chatTitle: String {
        store.currentSession?.title.isEmpty == false ? store.currentSession!.title : "New Chat"
    }

    /// The full request currently presented in the modal sheet, if any.
    private var presentedInputRequest: ChatInputRequest? {
        guard let id = presentedInputRequestId else { return nil }
        return store.currentInputRequests.first(where: { $0.id == id })
    }
}

/// Wrapper to make `ChatInputRequest` `Identifiable` for `.sheet(item:)`.
private struct IdentifiedRequest: Identifiable {
    let request: ChatInputRequest
    var id: String { request.id }
}

// MARK: - SessionSyncStatusBar

private struct SessionSyncStatusBar: View {
    let isSyncing: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(isSyncing ? "Syncing session…" : "Session content may be stale")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

private struct SessionDebugStatusBar: View {
    let connectionState: AHPConnection.ConnectionState
    let isSessionSyncing: Bool
    let isSessionStale: Bool
    let selectedSessionURI: String?
    let status: SessionDebugStatus

    var body: some View {
        Button(action: copyDebugDetails) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 7, height: 7)

                    Text("state \(connectionLabel)")
                        .fontWeight(.semibold)

                    Text("session \(sessionLabel)")
                        .foregroundStyle(.secondary)
                }

                Text(triggerLine)
                    .foregroundStyle(.secondary)

                Text(pathLine)
                    .foregroundStyle(.secondary)

                Text(timingLine)
                    .foregroundStyle(.secondary)
            }
            .font(.caption2.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Copies detailed session debug information")
    }

    private var connectionColor: Color {
        switch connectionState {
        case .connected: Color(.systemGreen)
        case .connecting, .reconnecting: .orange
        case .disconnected: .red
        }
    }

    private var connectionLabel: String {
        switch connectionState {
        case .connected: "connected"
        case .connecting: "connecting"
        case .reconnecting: "reconnecting"
        case .disconnected: "disconnected"
        }
    }

    private var sessionLabel: String {
        if isSessionSyncing { return "syncing" }
        if isSessionStale { return "stale" }
        return "ready"
    }

    private var triggerLine: String {
        let trigger = status.lastTrigger ?? "none"
        let detail = status.lastTriggerDetail.map { " (\($0))" } ?? ""
        return "trigger \(trigger)\(detail) · \(ageText(status.lastTriggerAt))"
    }

    private var pathLine: String {
        let labels = collapsedPathLabels
        guard !labels.isEmpty else { return "path none" }
        return "path " + labels.joined(separator: " -> ")
    }

    private var collapsedPathLabels: [String] {
        let labels = status.recentEvents.suffix(4).map(\.label)
        var collapsed: [String] = []
        for label in labels where collapsed.last != label {
            collapsed.append(label)
        }
        return collapsed
    }

    private var timingLine: String {
        let summaries = "summaries \(ageText(status.lastSessionSummariesFetchAt))"
        let session = status.lastSessionRefreshAt.map { _ in
            "session \(ageText(status.lastSessionRefreshAt))"
        } ?? "session never"
        let reconnect = "reconnect \(ageText(status.lastSuccessfulReconnectAt))"
        let state = "state \(ageText(status.lastConnectionStateChangeAt))"
        return "\(summaries) · \(session) · \(reconnect) · \(state)"
    }

    private var copyText: String {
        """
        state: \(connectionLabel)
        session: \(sessionLabel)
        selectedSessionURI: \(selectedSessionURI ?? "none")
        lastTrigger: \(status.lastTrigger ?? "none")
        lastTriggerDetail: \(status.lastTriggerDetail ?? "none")
        recentPath: \(status.recentEvents.map(\.label).joined(separator: " -> "))
        lastTriggerAt: \(copyDate(status.lastTriggerAt))
        lastConnectionStateChangeAt: \(copyDate(status.lastConnectionStateChangeAt))
        lastSuccessfulConnectAt: \(copyDate(status.lastSuccessfulConnectAt))
        lastSuccessfulReconnectAt: \(copyDate(status.lastSuccessfulReconnectAt))
        lastSessionSummariesFetchAt: \(copyDate(status.lastSessionSummariesFetchAt))
        lastSessionRefreshAt: \(copyDate(status.lastSessionRefreshAt))
        lastSessionRefreshURI: \(status.lastSessionRefreshURI ?? "none")
        """
    }

    private func copyDebugDetails() {
        UIPasteboard.general.string = copyText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func ageText(_ date: Date?) -> String {
        guard let date else { return "never" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    private func copyDate(_ date: Date?) -> String {
        guard let date else { return "never" }
        return date.ISO8601Format()
    }
}

// MARK: - InputBar

extension InputBar where ModelPicker == EmptyView {
    init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void) {
        self.init(text: text, isFocused: isFocused, modelPicker: nil) { _ in onSubmit() }
    }
}

struct InputBar<ModelPicker: View>: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    /// Sits in the box's bottom-left corner, across from Send.
    var modelPicker: ModelPicker?
    /// How to deliver it only matters while a turn is running.
    let onSubmit: (AppStore.Delivery) -> Void

    @Environment(AppStore.self) private var store

    private var isStreaming: Bool {
        store.currentChat?.activeTurn != nil
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let containerRadius: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            // Text field row
            TextField("Message the agent…", text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused(isFocused)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Toolbar row
            HStack(spacing: 12) {
                if let modelPicker {
                    modelPicker
                }
                Spacer(minLength: 0)

                if isStreaming {
                    // While the agent works: Stop, and — once there is
                    // something typed — Send, which steers by default (Next)
                    // and offers Now / Later on a long press.
                    if canSend {
                        Menu {
                            ForEach(AppStore.Delivery.allCases) { delivery in
                                Button {
                                    submit(delivery)
                                } label: {
                                    Label(delivery.title, systemImage: delivery.systemImage)
                                    Text(delivery.detail)
                                }
                            }
                        } label: {
                            circle(systemImage: "arrow.up", fill: .black, foreground: .white)
                        } primaryAction: {
                            submit(.next)
                        }
                        .accessibilityLabel("Send")
                        .accessibilityHint("Joins the current turn. Hold for Now or Later.")
                    }
                    Button {
                        Task { await store.cancelTurn() }
                    } label: {
                        circle(systemImage: "stop.fill", fill: Color(.systemGray5), foreground: .primary, ring: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop turn")
                } else {
                    Button {
                        submit(.next)
                    } label: {
                        circle(
                            systemImage: "arrow.up",
                            fill: canSend ? .black : Color(.systemGray3),
                            foreground: .white
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("Send message")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .glassInputBackground(cornerRadius: containerRadius)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func submit(_ delivery: AppStore.Delivery) {
        isFocused.wrappedValue = false
        onSubmit(delivery)
    }

    private func circle(systemImage: String, fill: Color, foreground: Color, ring: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 32, height: 32)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(Color(.systemGray3), lineWidth: ring ? 1 : 0))
    }
}

extension AppStore.Delivery {
    var title: String {
        switch self {
        case .now: "Now"
        case .next: "Next"
        case .later: "Later"
        }
    }

    var detail: String {
        switch self {
        case .now: "Stop and send this instead"
        case .next: "Join the current turn"
        case .later: "Send when this turn ends"
        }
    }

    var systemImage: String {
        switch self {
        case .now: "bolt"
        case .next: "arrow.turn.down.right"
        case .later: "clock"
        }
    }
}

// MARK: - Session Permission Picker

/// Session config properties that mean "how are tool calls approved", with the
/// values that identify each. A property is only treated as a permission
/// setting when every value it offers is one of these, so a host's unrelated
/// property that happens to share a name is left alone.
///
/// - `autoApprove`: VS Code / Copilot's setting.
/// - `permissionMode`: Claude Code's own modes, which `agent-host-server-claude`
///   exposes under Claude Code's names (Ask, Accept edits, Auto, Plan).
private let permissionConfigKeys: [(key: String, values: Set<String>)] = [
    ("autoApprove", ["default", "autoApprove", "autopilot"]),
    ("permissionMode", ["default", "acceptEdits", "auto", "plan", "bypassPermissions"]),
]

private struct SessionPermissionOption: Identifiable {
    let value: String
    let label: String

    var id: String { value }
}

private struct SessionModelOption: Identifiable {
    let id: String
    let label: String
}

private struct SessionPermissionPickerModel {
    /// The config property this picker reads and writes.
    let key: String
    let title: String
    let options: [SessionPermissionOption]
    let selectedValue: String
    /// False when the host fixes the setting for the session's life (not
    /// `sessionMutable`, or `readOnly`): the current mode is shown, not offered.
    let isMutable: Bool

    var selectedLabel: String {
        options.first(where: { $0.value == selectedValue })?.label ?? selectedValue
    }

    init?(session: SessionState) {
        guard let config = session.config else { return nil }
        let match = permissionConfigKeys.lazy.compactMap { candidate -> (String, SessionConfigPropertySchema, [AnyCodable], [String])? in
            guard let property = config.schema.properties[candidate.key],
                  property.type == "string",
                  // `enum` holds JSON values since 0.9.0; this picker only
                  // understands an all-string enum.
                  let rawValues = property.enum,
                  case let values = rawValues.compactMap({ $0.value as? String }),
                  values.count == rawValues.count,
                  values.contains("default"),
                  values.allSatisfy({ candidate.values.contains($0) }) else {
                return nil
            }
            return (candidate.key, property, rawValues, values)
        }.first
        guard let (key, property, _, values) = match else { return nil }

        let options = values.enumerated().map { index, value in
            let label: String
            if let labels = property.enumLabels, labels.indices.contains(index) {
                label = labels[index]
            } else {
                label = value
            }

            return SessionPermissionOption(
                value: value,
                label: label
            )
        }

        guard !options.isEmpty else { return nil }

        let currentValue = config.values[key]?.value as? String
        let selectedValue = currentValue.flatMap { value in
            options.contains(where: { $0.value == value }) ? value : nil
        } ?? "default"

        self.key = key
        self.title = property.title
        self.options = options
        self.selectedValue = selectedValue
        self.isMutable = property.sessionMutable == true && property.readOnly != true
    }
}

private struct SessionModelPickerModel {
    let title = "Model"
    let options: [SessionModelOption]
    let selectedValue: String?
    let selectedLabel: String

    init?(session: SessionState, agents: [AgentInfo], selectedModelId: String?) {
        guard let agent = agents.first(where: { $0.provider == session.provider }),
              !agent.models.isEmpty else {
            return nil
        }

        let options = agent.models.map { model in
            SessionModelOption(id: model.id, label: model.name)
        }
        let currentModelId = selectedModelId
        let selectedOption = currentModelId.flatMap { id in
            options.first(where: { $0.id == id })
        }

        self.options = options
        self.selectedValue = selectedOption?.id ?? currentModelId
        self.selectedLabel = selectedOption?.label ?? currentModelId ?? "Default model"
    }
}

/// The session's approval mode and model, in the message box's bottom-left
/// corner across from Send.
private struct SessionInlineAccessories: View {
    let permissionModel: SessionPermissionPickerModel?
    let modelPickerModel: SessionModelPickerModel?

    var body: some View {
        HStack(spacing: 14) {
            if let permissionModel {
                SessionPermissionPickerView(model: permissionModel, inline: true)
            }
            if let modelPickerModel {
                SessionModelPickerView(model: modelPickerModel, inline: true)
            }
        }
    }
}

private struct SessionPermissionPickerView: View {
    let model: SessionPermissionPickerModel
    var inline = false

    @Environment(AppStore.self) private var store

    var body: some View {
        if model.isMutable {
            menu
        } else {
            // Fixed when the session was created: show it, don't offer it.
            SessionAccessoryButtonLabel(
                systemImage: "lock.shield",
                text: model.selectedLabel,
                isMenu: false,
                inline: inline
            )
            .opacity(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.title)
            .accessibilityValue(model.selectedLabel)
            .accessibilityHint("Chosen when the session was created")
        }
    }

    private var menu: some View {
        Menu {
            ForEach(model.options) { option in
                Button {
                    guard option.value != model.selectedValue else { return }
                    Task {
                        await store.setSessionConfigValue(
                            property: model.key,
                            value: AnyCodable(option.value)
                        )
                    }
                } label: {
                    if option.value == model.selectedValue {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            SessionAccessoryButtonLabel(
                systemImage: "lock.shield",
                text: model.selectedLabel,
                inline: inline
            )
        }
        .accessibilityLabel(model.title)
        .accessibilityValue(model.selectedLabel)
        .tint(.primary)
    }
}

private struct SessionModelPickerView: View {
    let model: SessionModelPickerModel
    /// Drawn inside the message box: no glass capsule of its own.
    var inline = false

    @Environment(AppStore.self) private var store

    var body: some View {
        Menu {
            ForEach(model.options) { option in
                Button {
                    guard option.id != model.selectedValue else { return }
                    Task {
                        await store.changeModel(option.id)
                    }
                } label: {
                    if option.id == model.selectedValue {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            SessionAccessoryButtonLabel(
                systemImage: "cpu",
                text: model.selectedLabel,
                inline: inline
            )
        }
        .accessibilityLabel(model.title)
        .accessibilityValue(model.selectedLabel)
        .tint(.primary)
    }
}

private struct SessionAccessoryButtonLabel: View {
    let systemImage: String
    let text: String
    /// False for a value shown but not offered: no chevron promising a menu.
    var isMenu = true
    /// Drawn inside the message box: no glass capsule of its own.
    var inline = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))

            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if isMenu {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .modifier(AccessoryChrome(inline: inline))
    }
}

private struct AccessoryChrome: ViewModifier {
    let inline: Bool

    func body(content: Content) -> some View {
        if inline {
            content
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        } else {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassInputBackground(cornerRadius: 16)
        }
    }
}

// MARK: - Glass Background

private extension View {
    @ViewBuilder
    func glassInputBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - TurnView (completed)

struct TurnView: View {
    let turn: Turn
    let activeTurnId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User message
            UserBubble(text: turn.message.text, attachments: turn.message.attachments)

            // Response parts
            ResponsePartsView(parts: turn.responseParts)

            if turn.state == .cancelled {
                Label("Cancelled", systemImage: "xmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5), in: Capsule())
            }

            // The details the user chose (time, tokens, …)
            TurnDetailsLine(facts: TurnFacts(turn))
        }
    }
}

// MARK: - ActiveTurnView (streaming)

struct ActiveTurnView: View {
    let turn: ActiveTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UserBubble(text: turn.message.text, attachments: turn.message.attachments)

            ResponsePartsView(parts: turn.responseParts)

            // Streaming indicator
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6), in: Capsule())

            TurnDetailsLine(facts: TurnFacts(turn))
        }
    }
}

// MARK: - PendingMessageView (queued / steering)

/// Renders a pending user message — either a queued message (will start
/// a new turn after the current one finishes, or immediately if the
/// session is idle) or a steering message (will be injected into the
/// current turn at the server's next opportunity).
struct PendingMessageView: View {
    let message: PendingMessage
    let caption: String
    let captionIcon: String
    /// Takes the message back; nil when it can't be (already sent).
    var onRemove: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            UserBubble(text: message.message.text, attachments: message.message.attachments)
                .opacity(0.7)

            HStack(spacing: 4) {
                Image(systemName: captionIcon)
                    .font(.caption2)
                Text(caption)
                    .font(.caption2)
                if let onRemove {
                    Button("Cancel", action: onRemove)
                        .font(.caption2.weight(.semibold))
                        .padding(.leading, 6)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.trailing, 4)
        }
    }
}

// MARK: - ReconnectProgressBar

/// Floating horizontal progress indicator shown at the top of the chat view
/// while a connect or reconnect is in flight, saying which stage it is in.
private struct ReconnectProgressBar: View {
    let stage: ConnectionStage
    let serverName: String?

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            ConnectionStageText(stage: stage, serverName: serverName, fallback: "Reconnecting…")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .padding(.top, 8)
    }
}


/// A nav-bar button that forces a reconnect, useful for testing the reconnect flow
/// without having to lock the screen or kill the network.

// MARK: - AuthRequiredPanel

/// Inline panel shown in the chat view when the selected session's agent has
/// rejected our request with `AuthRequired` (-32007). Lets the user paste a
/// bearer token (e.g. a GitHub PAT) that we forward to the server via the
/// `authenticate` JSON-RPC command, then retries the subscribe.
private struct AuthRequiredPanel: View {
    @Environment(AppStore.self) private var store
    let session: SessionState?

    @State private var token: String = ""
    @FocusState private var tokenFocused: Bool

    private var providerLabel: String {
        if let provider = session?.provider, !provider.isEmpty {
            return provider
        }
        return "this agent"
    }

    private var resources: [ProtectedResourceMetadata] {
        store.currentAuthRequiredResources
    }

    private var primaryResource: ProtectedResourceMetadata? { resources.first }

    private var isAuthenticating: Bool {
        guard let uri = store.selectedSessionURI else { return false }
        return store.authenticatingSessions.contains(uri)
    }

    private var canSubmit: Bool {
        !isAuthenticating &&
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !resources.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                Text("Sign-in required")
                    .font(.headline)
                Spacer()
            }

            Text("\(providerLabel) needs a bearer token before this session can load. Paste a token below and we'll send it to the server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let resource = primaryResource {
                resourceDetails(resource)
            }

            SecureField("Bearer token", text: $token)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($tokenFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .disabled(isAuthenticating || resources.isEmpty)

            HStack(spacing: 8) {
                Button {
                    Task {
                        let captured = token
                        let ok = await store.authenticateCurrentSession(token: captured)
                        if ok { token = "" }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isAuthenticating {
                            ProgressView().controlSize(.small)
                        }
                        Text(isAuthenticating ? "Signing in…" : "Sign in")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .disabled(!canSubmit)

                Button {
                    Task {
                        if let uri = store.selectedSessionURI {
                            await store.selectSession(uri: uri, debugTrigger: "manual retry")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .disabled(isAuthenticating)
                .accessibilityLabel("Retry without signing in")
            }

            if resources.isEmpty {
                Text("The server didn't advertise an authentication target. Try reconnecting or check the agent's configuration on the host.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func resourceDetails(_ resource: ProtectedResourceMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = resource.resourceName, !name.isEmpty {
                Text(name)
                    .font(.subheadline.weight(.medium))
            }
            Text(resource.resource)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            if let docs = resource.resourceDocumentation, let url = URL(string: docs) {
                Link(destination: url) {
                    Label("How to get a token", systemImage: "arrow.up.forward")
                        .font(.footnote.weight(.medium))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Preview Helpers

private struct InputBarPreviewWrapper: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        InputBar(text: $text, isFocused: $isFocused) { }
    }
}

// MARK: - Previews

#Preview("Conversation Flow", traits: .fixedLayout(width: 390, height: 2400)) {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            // Turn 1: Simple question → markdown response
            UserBubble(
                text: "What does the auth module do?",
                attachments: nil
            )
            MarkdownPartView(part: MarkdownResponsePart(
                kind: .markdown,
                id: "m1",
                content: "The auth module handles **JWT-based authentication**. It provides `login()`, `logout()`, and `refreshToken()` functions that manage session state without server-side cookies."
            ))

            // Turn 2: XML context + attachments → reasoning + tool calls + markdown
            UserBubble(
                text: """
                <reminder>
                IMPORTANT: check existing tests before making changes.
                </reminder>
                <userRequest>
                Can you refactor it to use async/await?
                </userRequest>
                """,
                attachments: [
                    .resource(MessageResourceAttachment(label: "auth.swift", displayKind: "document", uri: "src/auth.swift", type: .resource))
                ]
            )
            ReasoningPartView(part: ReasoningResponsePart(
                kind: .reasoning,
                id: "r1",
                content: "I need to check the current implementation first, then convert the completion handler patterns to async/await."
            ))
            ToolCallPartView(toolCall: .completed(ToolCallCompletedState(
                toolCallId: "tc1",
                toolName: "readFile",
                displayName: "Read file",
                invocationMessage: .string("Reading src/auth.swift"),
                toolInput: .contentRef(ContentRef(uri: "file:///tool-inputs/tc1.json")),
                success: true,
                pastTenseMessage: .string("Read src/auth.swift"),
                confirmed: .notNeeded,
                status: .completed
            )))
            ToolCallPartView(toolCall: .completed(ToolCallCompletedState(
                toolCallId: "tc2",
                toolName: "editFile",
                displayName: "Edit file",
                invocationMessage: .string("Editing src/auth.swift"),
                toolInput: .contentRef(ContentRef(uri: "file:///tool-inputs/tc2.json")),
                success: true,
                pastTenseMessage: .string("Edited src/auth.swift"),
                confirmed: .notNeeded,
                status: .completed
            )))
            MarkdownPartView(part: MarkdownResponsePart(
                kind: .markdown,
                id: "m2",
                content: "I've refactored the auth module to use `async/await`. The key changes:\n\n- `login()` → `async throws`\n- `refreshToken()` → `async throws`\n- Removed callback-based API"
            ))

            // Turn 3: Tool needing confirmation
            UserBubble(
                text: "Now deploy it",
                attachments: nil
            )
            ToolCallPartView(toolCall: .pendingConfirmation(ToolCallPendingConfirmationState(
                toolCallId: "tc3",
                toolName: "bash",
                displayName: "Run command",
                invocationMessage: .string("Run: npm run deploy --production"),
                toolInput: .inline("{\"command\": \"npm run deploy --production\"}"),
                status: .pendingConfirmation,
                confirmationTitle: .string("Allow production deployment?")
            )))

            // Turn 4: Active turn with running tool
            UserBubble(
                text: "While that's pending, explain the token refresh flow",
                attachments: nil
            )
            ToolCallPartView(toolCall: .running(ToolCallRunningState(
                toolCallId: "tc4",
                toolName: "readFile",
                displayName: "Read file",
                invocationMessage: .string("Reading src/auth/token.swift"),
                toolInput: .contentRef(ContentRef(uri: "file:///tool-inputs/tc4.json")),
                confirmed: .notNeeded,
                status: .running
            )))

            // Floating input
            InputBarPreviewWrapper()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
    .environment(AppStore())
}
