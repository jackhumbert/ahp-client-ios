import AgentHostProtocol
import Foundation
import Testing
@testable import AHPApp

/// Which turn, if any, the app offers to resume: exactly the one the package
/// reducer would accept a `chatTurnResume` for.
@MainActor
struct TurnResumeTests {
    private func errorPart(resumable: Bool?) -> ResponsePart {
        .error(ErrorResponsePart(
            kind: .error,
            error: ErrorInfo(errorType: "hostRestarted", message: "Host restarted"),
            resumable: resumable
        ))
    }

    private func turn(_ id: String, state: TurnState = .error, parts: [ResponsePart]) -> Turn {
        Turn(
            id: id,
            startedAt: "2026-01-01T00:00:00.000Z",
            message: Message(text: id, origin: MessageOrigin(kind: .user)),
            responseParts: parts,
            state: state
        )
    }

    private func chat(turns: [Turn], active: ActiveTurn? = nil) -> ChatState {
        var state = ChatState(
            resource: "ahp-chat:/c",
            title: "",
            status: .idle,
            modifiedAt: "2026-01-01T00:00:00.000Z",
            turns: turns
        )
        state.activeTurn = active
        return state
    }

    @Test func aResumableLastTurnIsOffered() {
        let state = chat(turns: [turn("t1", parts: [errorPart(resumable: true)])])
        #expect(AppStore.resumableTurnID(in: state) == "t1")
    }

    @Test func anErrorTheHostDidNotMarkResumableIsNot() {
        #expect(AppStore.resumableTurnID(in: chat(turns: [turn("t1", parts: [errorPart(resumable: false)])])) == nil)
        #expect(AppStore.resumableTurnID(in: chat(turns: [turn("t1", parts: [errorPart(resumable: nil)])])) == nil)
    }

    @Test func nothingResumesWhileATurnIsActive() {
        let active = ActiveTurn(
            id: "t2",
            startedAt: "2026-01-01T00:00:01.000Z",
            message: Message(text: "t2", origin: MessageOrigin(kind: .user)),
            responseParts: []
        )
        let state = chat(turns: [turn("t1", parts: [errorPart(resumable: true)])], active: active)
        #expect(AppStore.resumableTurnID(in: state) == nil)
    }

    @Test func theErrorMustBeTheTurnsLastPart() {
        let text = ResponsePart.markdown(MarkdownResponsePart(kind: .markdown, id: "m", content: "hi"))
        let state = chat(turns: [turn("t1", parts: [errorPart(resumable: true), text])])
        #expect(AppStore.resumableTurnID(in: state) == nil)
    }

    @Test func onlyTheLastTurnCanResume() {
        let state = chat(turns: [
            turn("t1", parts: [errorPart(resumable: true)]),
            turn("t2", state: .complete, parts: []),
        ])
        #expect(AppStore.resumableTurnID(in: state) == nil)
    }
}
