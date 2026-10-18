import AgentHostProtocol
import SwiftUI

// MARK: - ChatTitleMenu

/// The chat view's title. When the session has more than one chat — side
/// chats, subagents' worker chats — it is also the menu that switches between
/// them, and names the chat open now under the session's title.
struct ChatTitleMenu: View {
    @Environment(AppStore.self) private var store
    let sessionTitle: String

    var body: some View {
        let chats = store.currentSessionChats
        if chats.count > 1 {
            Menu {
                // Buttons rather than a Picker: a menu button shows a second
                // Text as its subtitle, and a Picker row drops it.
                ForEach(chats, id: \.resource) { chat in
                    let kind = ChatKind(chat, defaultChat: store.currentDefaultChatURI)
                    let isOpen = chat.resource == store.currentChatURI
                    Button {
                        store.selectChat(chat.resource)
                    } label: {
                        Text(chat.title.isEmpty ? "Untitled chat" : chat.title)
                        Text(kind.caption(status: chat.status))
                        Image(systemName: isOpen ? "checkmark" : kind.systemImage)
                    }
                    .accessibilityAddTraits(isOpen ? .isSelected : [])
                }
            } label: {
                title(chatTitle: openChatTitle, showChevron: true)
            }
            .accessibilityHint("Switches between this session's chats")
        } else {
            title(chatTitle: nil, showChevron: false)
        }
    }

    /// The open chat's title, when it is not the session's main chat.
    private var openChatTitle: String? {
        guard let uri = store.currentChatURI, uri != store.currentDefaultChatURI else { return nil }
        let chat = store.currentSessionChats.first { $0.resource == uri }
        return chat.map { $0.title.isEmpty ? "Untitled chat" : $0.title }
    }

    // A smaller title than the navigation bar's own: chat titles are the
    // first message, and long.
    private func title(chatTitle: String?, showChevron: Bool) -> some View {
        HStack(spacing: 4) {
            VStack(spacing: 0) {
                Text(sessionTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let chatTitle {
                    Text(chatTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a chat is to the session it belongs to, for its icon and caption.
enum ChatKind: Equatable {
    case main, user, fork, sideChat, subagent

    init(_ chat: ChatSummary, defaultChat: String?) {
        if chat.resource == defaultChat {
            self = .main
            return
        }
        switch chat.origin {
        case .fork: self = .fork
        case .sideChat: self = .sideChat
        case .tool: self = .subagent
        default: self = .user
        }
    }

    var systemImage: String {
        switch self {
        case .main: "bubble.left.and.bubble.right"
        case .user: "bubble.left"
        case .fork: "arrow.triangle.branch"
        case .sideChat: "arrow.turn.down.right"
        case .subagent: "person.2"
        }
    }

    func caption(status: SessionStatus) -> String {
        let kind = switch self {
        case .main: "Main chat"
        case .user: "Chat"
        case .fork: "Fork"
        case .sideChat: "Side chat"
        case .subagent: "Subagent"
        }
        if status.needsInput { return "\(kind) · needs you" }
        if status.isWorking { return "\(kind) · working" }
        return kind
    }
}

// MARK: - BackgroundWorkBar

/// Work a chat's agent left running past its turns — background shells and
/// subagents — as one line that opens into a list. A shell opens its terminal;
/// a subagent opens its worker chat.
struct BackgroundWorkBar: View {
    @Environment(AppStore.self) private var store
    let work: [BackgroundWork]
    var onOpenTerminal: (String) -> Void
    @State private var isExpanded = false

    private var items: [BackgroundWorkItem] {
        work.compactMap(BackgroundWorkItem.init)
    }

    var body: some View {
        let items = items
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(items.count == 1 ? "1 running in the background" : "\(items.count) running in the background")
                            .font(.caption.weight(.medium))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 0 : 180))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                if isExpanded {
                    Divider()
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private func row(_ item: BackgroundWorkItem) -> some View {
        let action: (() -> Void)? = switch item.target {
        case .terminal(let uri): { onOpenTerminal(uri) }
        case .chat(let uri): { store.selectChat(uri) }
        case .none: nil
        }
        Button {
            action?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if let started = item.startedAt {
                    Text(started, style: .relative)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

/// One background entry, reduced to what the bar shows.
struct BackgroundWorkItem: Identifiable, Equatable {
    enum Target: Equatable {
        case terminal(String)
        case chat(String)
    }

    let id: String
    let label: String
    let detail: String?
    let systemImage: String
    let startedAt: Date?
    let target: Target?

    /// Nil for a kind this app does not know, which it leaves out.
    init?(_ work: BackgroundWork) {
        switch work {
        case .shell(let shell):
            id = shell.id
            label = shell.label
            detail = shell.command
            systemImage = "terminal"
            startedAt = AHPTimestamp.date(from: shell.startedAt)
            target = shell.terminal.map(Target.terminal)
        case .subagent(let subagent):
            id = subagent.id
            label = subagent.label
            detail = nil
            systemImage = "person.2"
            startedAt = AHPTimestamp.date(from: subagent.startedAt)
            target = .chat(subagent.chat)
        case .unknown:
            return nil
        }
    }
}

// MARK: - ReadOnlyChatBar

/// Stands in for the message box in a chat the user can only watch, such as a
/// subagent's worker chat, with the way back to the main conversation.
struct ReadOnlyChatBar: View {
    /// Replaces the default line, for a chat that is only quiet for now.
    var caption = "Another agent writes to this chat. You can watch it here."

    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Main chat") {
                store.selectChat(nil)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}
