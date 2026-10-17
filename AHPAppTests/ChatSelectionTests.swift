import AgentHostProtocol
import Foundation
import Testing
@testable import AHPApp

/// Opening a chat other than a session's default: which chats are offered,
/// which one is open, and when the choice falls back to the default.
@MainActor
struct ChatSelectionTests {
    static let session = "echo:/session-1"
    static let main = "ahp-chat:/main"
    static let side = "ahp-chat:/side"
    static let worker = "ahp-chat:/worker"
    static let hidden = "ahp-chat:/hidden"
    static let archived = "ahp-chat:/archived"

    static func chat(
        _ resource: String,
        status: SessionStatus = .idle,
        origin: ChatOrigin? = nil,
        interactivity: ChatInteractivity? = nil
    ) -> ChatSummary {
        ChatSummary(
            resource: resource,
            title: resource,
            status: status,
            modifiedAt: "2026-01-01T00:00:00.000Z",
            origin: origin,
            interactivity: interactivity
        )
    }

    static func sessionState(chats: [ChatSummary]) -> SessionState {
        SessionState(
            provider: "echo",
            title: "Session",
            status: .idle,
            lifecycle: .ready,
            activeClients: [],
            chats: chats,
            defaultChat: main
        )
    }

    static let allChats = [
        chat(main),
        chat(side, origin: .sideChat(ChatOriginSideChat(kind: .sideChat, chat: main, turnId: "t1"))),
        chat(worker, status: .inProgress,
             origin: .tool(ChatOriginTool(chat: main, toolCallId: "call-1")),
             interactivity: .readOnly),
        chat(hidden, interactivity: .hidden),
        chat(archived, status: [.idle, .isArchived]),
    ]

    /// A store showing `session` with `chats`.
    static func store(chats: [ChatSummary] = allChats) -> AppStore {
        let store = AppStore()
        store.selectedSessionURI = session
        store.applySnapshot(Snapshot(resource: session, state: .session(sessionState(chats: chats)), fromSeq: 1))
        return store
    }

    @Test func theDefaultChatIsOpenAtFirst() {
        let store = Self.store()
        #expect(store.currentChatURI == Self.main)
        #expect(store.currentDefaultChatURI == Self.main)
        #expect(!store.isCurrentChatReadOnly)
    }

    @Test func hiddenAndArchivedChatsAreNotOffered() {
        let store = Self.store()
        #expect(store.currentSessionChats.map(\.resource) == [Self.main, Self.side, Self.worker])
    }

    @Test func selectingAChatOpensIt() {
        let store = Self.store()
        store.selectChat(Self.side)
        #expect(store.currentChatURI == Self.side)
        #expect(!store.isCurrentChatReadOnly)
    }

    @Test func aWorkerChatIsReadOnly() {
        let store = Self.store()
        store.selectChat(Self.worker)
        #expect(store.currentChatURI == Self.worker)
        #expect(store.isCurrentChatReadOnly)
    }

    @Test func anArchivedChatStaysListedWhileItIsOpen() {
        let store = Self.store()
        store.selectChat(Self.archived)
        #expect(store.currentSessionChats.map(\.resource).contains(Self.archived))
    }

    @Test func aChatTheSessionDoesNotListIsIgnored() {
        let store = Self.store()
        store.selectChat(Self.side)
        store.selectChat("ahp-chat:/elsewhere")
        #expect(store.currentChatURI == Self.side)
    }

    @Test func nilGoesBackToTheDefault() {
        let store = Self.store()
        store.selectChat(Self.worker)
        store.selectChat(nil)
        #expect(store.currentChatURI == Self.main)
    }

    @Test func aRemovedChatFallsBackToTheDefault() {
        let store = Self.store()
        store.selectChat(Self.worker)
        let remaining = Self.allChats.filter { $0.resource != Self.worker }
        store.applySnapshot(Snapshot(
            resource: Self.session,
            state: .session(Self.sessionState(chats: remaining)),
            fromSeq: 2
        ))
        #expect(store.currentChatURI == Self.main)
    }

    @Test func eachSessionKeepsItsOwnChoice() {
        let store = Self.store()
        store.selectChat(Self.side)
        let other = "echo:/session-2"
        store.selectedSessionURI = other
        store.applySnapshot(Snapshot(resource: other, state: .session(Self.sessionState(chats: Self.allChats)), fromSeq: 1))
        #expect(store.currentChatURI == Self.main)
        store.selectedSessionURI = Self.session
        #expect(store.currentChatURI == Self.side)
    }

    @Test func chatKindsComeFromOriginAndDefault() {
        let chats = Self.allChats
        #expect(ChatKind(chats[0], defaultChat: Self.main) == .main)
        #expect(ChatKind(chats[1], defaultChat: Self.main) == .sideChat)
        #expect(ChatKind(chats[2], defaultChat: Self.main) == .subagent)
        #expect(ChatKind(chats[2], defaultChat: Self.main).caption(status: .inProgress) == "Subagent · working")
        #expect(ChatKind(chats[3], defaultChat: Self.main) == .user)
    }
}

struct BackgroundWorkItemTests {
    private func decode(_ json: String) throws -> BackgroundWork {
        try JSONDecoder().decode(BackgroundWork.self, from: Data(json.utf8))
    }

    @Test func aShellOpensItsTerminal() throws {
        let work = try decode("""
        {"kind": "shell", "id": "s1", "label": "Build", "startedAt": "2026-01-01T00:00:00.000Z",
         "command": "make all", "terminal": "ahp-terminal:/t1"}
        """)
        let item = try #require(BackgroundWorkItem(work))
        #expect(item.label == "Build")
        #expect(item.detail == "make all")
        #expect(item.target == .terminal("ahp-terminal:/t1"))
        #expect(item.startedAt != nil)
    }

    @Test func aShellWithoutATerminalOpensNothing() throws {
        let work = try decode("""
        {"kind": "shell", "id": "s1", "label": "Build", "startedAt": "2026-01-01T00:00:00Z", "command": "make"}
        """)
        #expect(BackgroundWorkItem(work)?.target == nil)
    }

    @Test func aSubagentOpensItsChat() throws {
        let work = try decode("""
        {"kind": "subagent", "id": "a1", "label": "Researcher", "startedAt": "2026-01-01T00:00:00Z",
         "chat": "ahp-chat:/worker"}
        """)
        #expect(BackgroundWorkItem(work)?.target == .chat("ahp-chat:/worker"))
    }

    @Test func anUnknownKindIsLeftOut() throws {
        let work = try decode("""
        {"kind": "notebook", "id": "n1", "label": "Cells", "startedAt": "2026-01-01T00:00:00Z"}
        """)
        #expect(BackgroundWorkItem(work) == nil)
    }
}
