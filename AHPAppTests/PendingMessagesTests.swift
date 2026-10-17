import AgentHostProtocol
import Foundation
import Testing
@testable import AHPApp

/// Steering and queued messages as the chat shows them, from a 1.1.0 host's
/// shared list or a 1.0.0 host's separate steering slot.
struct PendingMessagesTests {
    private func pending(_ id: String, _ kind: PendingMessageKind? = nil) -> PendingMessage {
        PendingMessage(id: id, kind: kind, message: Message(text: id, origin: MessageOrigin(kind: .user)))
    }

    private func chat(steering: PendingMessage? = nil, queued: [PendingMessage]? = nil) -> ChatState {
        var state = ChatState(
            resource: "ahp-chat:/c",
            title: "",
            status: .inProgress,
            modifiedAt: "2026-01-01T00:00:00.000Z",
            turns: []
        )
        state.steeringMessage = steering
        state.queuedMessages = queued
        return state
    }

    private func summary(_ state: ChatState) -> [String] {
        state.pendingMessages.map { "\($0.id):\($0.kind == .steering ? "steering" : "queued")" }
    }

    @Test func aSharedListIsShownInItsOwnOrderWithoutTheMirrorTwice() {
        // The spec's mixed snapshot: the mirror names a steering entry that is
        // also in the list, and an entry from before 1.1.0 has no kind.
        let state = chat(
            steering: pending("s", .steering),
            queued: [pending("old"), pending("q", .queued), pending("s", .steering)]
        )
        #expect(summary(state) == ["old:queued", "q:queued", "s:steering"])
    }

    @Test func aMirrorOnlyInTheSlotComesFirst() {
        // A 1.0.0 host: steering lives only in `steeringMessage`.
        let state = chat(steering: pending("s"), queued: [pending("q")])
        #expect(summary(state) == ["s:steering", "q:queued"])
    }

    @Test func anUntaggedEntryTheMirrorNamesIsSteering() {
        let state = chat(steering: pending("s"), queued: [pending("s"), pending("q")])
        #expect(summary(state) == ["s:steering", "q:queued"])
    }

    @Test func severalSteeringMessagesAreAllShown() {
        let state = chat(
            steering: pending("s2", .steering),
            queued: [pending("s1", .steering), pending("s2", .steering), pending("q", .queued)]
        )
        #expect(summary(state) == ["s1:steering", "s2:steering", "q:queued"])
    }

    @Test func removingASteeringMessageLeavesNoQueuedCopy() {
        // The 1.0.0 reducer cleared only the slot, so the list's copy stayed
        // on screen as "Later" until the next snapshot.
        var state = chat()
        state = chatReducer(state: state, action: .chatPendingMessageSet(ChatPendingMessageSetAction(
            type: .chatPendingMessageSet, kind: .steering, id: "s",
            message: Message(text: "s", origin: MessageOrigin(kind: .user))
        )))
        #expect(summary(state) == ["s:steering"])
        state = chatReducer(state: state, action: .chatPendingMessageRemoved(ChatPendingMessageRemovedAction(
            type: .chatPendingMessageRemoved, kind: .steering, id: "s"
        )))
        #expect(state.pendingMessages.isEmpty)
    }

    @Test func nothingWaitingIsEmpty() {
        #expect(chat().pendingMessages.isEmpty)
    }
}
