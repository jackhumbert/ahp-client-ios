import AgentHostProtocol
import Foundation
import Testing
@testable import AHPApp

/// The fold of a workflow run's `ahp-py/flow` descriptors, a port of ahp-py's
/// `flow.run_view`. Fixtures are wire JSON shaped like `flow.py`'s builders,
/// decoded into `ResponsePart` the way the app receives them.
@MainActor
struct FlowRunTests {
    // MARK: - Fixtures

    private func part(_ json: String) throws -> ResponsePart {
        try JSONDecoder().decode(ResponsePart.self, from: Data(json.utf8))
    }

    /// A `systemNotification` part whose descriptor is `descriptor` (JSON).
    private func notice(_ descriptor: String) throws -> ResponsePart {
        try part("""
        {"kind": "systemNotification", "content": "flow", "_meta": {"ahp-py/flow": \(descriptor)}}
        """)
    }

    private func runStarted(_ runID: String = "run-1", workflow: String = "review") throws -> ResponsePart {
        try notice(#"{"runStarted": {"runId": "\#(runID)", "workflow": "\#(workflow)"}}"#)
    }

    private func phaseStarted(_ title: String) throws -> ResponsePart {
        try notice(#"{"phaseStarted": {"title": "\#(title)"}}"#)
    }

    private func phaseFinished(_ title: String) throws -> ResponsePart {
        try notice(#"{"phaseFinished": {"title": "\#(title)"}}"#)
    }

    private func runFinished(_ status: String, error: String? = nil) throws -> ResponsePart {
        let error = error.map { #", "error": "\#($0)""# } ?? ""
        return try notice(#"{"runFinished": {"status": "\#(status)"\#(error)}}"#)
    }

    /// `step_started(...)` as JSON.
    private func started(_ ordinal: Int, phase: String? = "Plan", chat: String? = nil) -> String {
        let phase = phase.map { "\"\($0)\"" } ?? "null"
        let chat = chat.map { "\"\($0)\"" } ?? "null"
        return """
        {"ordinal": \(ordinal), "label": "step \(ordinal)", "phase": \(phase), \
        "chat": \(chat), "model": "model-a", "provider": "provider-a"}
        """
    }

    /// `step_finished(...)` as JSON.
    private func finished(
        _ status: String = "ok", result: String = #""done""#, input: Int = 10, output: Int = 5,
        error: String? = nil
    ) -> String {
        let error = error.map { #", "error": "\#($0)""# } ?? ""
        return """
        {"status": "\(status)", "result": \(result), \
        "usage": {"inputTokens": \(input), "outputTokens": \(output)}\(error)}
        """
    }

    /// A `toolCall` part in state `status` whose descriptor is `descriptor`.
    private func toolCall(_ id: String, status: String = "completed", descriptor: String) throws -> ResponsePart {
        let stateFields: String
        switch status {
        case "completed":
            stateFields = #""success": true, "pastTenseMessage": "Ran", "confirmed": "not-needed""#
        case "running":
            stateFields = #""confirmed": "not-needed""#
        case "cancelled":
            stateFields = #""reason": "skipped""#
        default:
            stateFields = #""extra": 1"#
        }
        return try part("""
        {"kind": "toolCall", "toolCall": {"status": "\(status)", "toolCallId": "\(id)", \
        "toolName": "step", "displayName": "Step", "invocationMessage": "Running", \(stateFields), \
        "_meta": {"ahp-py/flow": \(descriptor)}}}
        """)
    }

    private func step(_ id: String, status: String = "completed", started: String, finished: String? = nil,
                      awaiting: Bool = false) throws -> ResponsePart {
        var body = #"{"stepStarted": \#(started)"#
        if let finished { body += #", "stepFinished": \#(finished)"# }
        if awaiting { body += #", "awaitingInput": true"# }
        return try toolCall(id, status: status, descriptor: body + "}")
    }

    // MARK: - Tests

    @Test func partsWithoutARunFoldToNil() throws {
        let parts = [
            try part(#"{"kind": "markdown", "id": "m", "content": "hi"}"#),
            try phaseStarted("Plan"),
            try step("t1", started: started(0), finished: finished()),
        ]
        #expect(FlowRunView.fold(parts: parts, turnState: .complete, isActive: false) == nil)
    }

    @Test func aFinishedRun() throws {
        let parts = [
            try runStarted(),
            try phaseStarted("Plan"),
            try step("t0", started: started(0), finished: finished(input: 10, output: 5)),
            try phaseFinished("Plan"),
            try phaseStarted("Build"),
            try step("t1", started: started(1, phase: "Build"),
                     finished: finished("skipped", result: "null", input: 0, output: 0)),
            try step("t2", started: started(2, phase: "Build"),
                     finished: finished("error", input: 3, output: 4, error: "boom")),
            try phaseFinished("Build"),
            try runFinished("error", error: "step 2 failed"),
        ]
        let run = try #require(FlowRunView.fold(parts: parts, turnState: .complete, isActive: false))
        #expect(run.runID == "run-1")
        #expect(run.workflow == "review")
        #expect(run.status == .error)
        #expect(run.error == "step 2 failed")
        #expect(run.phases.map(\.title) == ["Plan", "Build"])
        #expect(run.phases.map(\.status) == [.finished, .finished])
        #expect(run.phases[1].steps.map(\.status) == [.skipped, .error])
        #expect(run.phases[1].steps[1].error == "boom")
        #expect(run.phases[0].steps[0].result == AnyCodable("done"))
        #expect(run.phases[1].steps[0].result == nil)
        #expect(run.usage == FlowUsage(inputTokens: 13, outputTokens: 9))
        #expect(run.steps.map(\.toolCallID) == ["t0", "t1", "t2"])
        #expect(run.steps[0].label == "step 0")
        #expect(run.steps[0].model == "model-a")
        #expect(run.steps[0].provider == "provider-a")
    }

    @Test func aRunWithoutRunFinishedTakesTheTurnsEnding() throws {
        let parts = [try runStarted(), try phaseStarted("Plan")]
        #expect(FlowRunView.fold(parts: parts, turnState: .complete, isActive: false)?.status == .ok)
        #expect(FlowRunView.fold(parts: parts, turnState: .error, isActive: false)?.status == .error)
        #expect(FlowRunView.fold(parts: parts, turnState: nil, isActive: true)?.status == .running)
        // runFinished outranks an active turn.
        let done = parts + [try runFinished("ok")]
        #expect(FlowRunView.fold(parts: done, turnState: nil, isActive: true)?.status == .ok)
    }

    @Test func anActiveRunWithAnAwaitingStep() throws {
        let parts = [
            try runStarted(),
            try phaseStarted("Plan"),
            try step("t0", started: started(0), finished: finished()),
            try phaseFinished("Plan"),
            try phaseStarted("Build"),
            try step("t1", status: "running", started: started(1, phase: "Build", chat: "ahp-chat:/w1"),
                     awaiting: true),
            try step("t2", status: "running", started: started(2, phase: "Build")),
        ]
        let run = try #require(FlowRunView.fold(parts: parts, turnState: nil, isActive: true))
        #expect(run.status == .running)
        #expect(run.phases.map(\.status) == [.finished, .running])
        let build = run.phases[1].steps
        #expect(build.map(\.status) == [.running, .running])
        #expect(build.map(\.awaiting) == [true, false])
        #expect(build[0].chat == "ahp-chat:/w1")
        #expect(build[0].usage == nil)
        #expect(run.usage == FlowUsage(inputTokens: 10, outputTokens: 5))
    }

    @Test func aCancelledTurnCancelsWhatWasStillRunning() throws {
        let parts = [
            try runStarted(),
            try phaseStarted("Plan"),
            try step("t0", started: started(0), finished: finished()),
            try step("t1", status: "running", started: started(1), awaiting: true),
        ]
        let run = try #require(FlowRunView.fold(parts: parts, turnState: .cancelled, isActive: false))
        #expect(run.status == .cancelled)
        #expect(run.phases.map(\.status) == [.finished])
        #expect(run.steps.map(\.status) == [.ok, .cancelled])
        // Awaiting only while running.
        #expect(run.steps[1].awaiting == false)
    }

    @Test func aCancelledToolCallIsACancelledStepWhileTheRunGoesOn() throws {
        let parts = [
            try runStarted(),
            try step("t0", status: "cancelled", started: started(0)),
        ]
        let run = try #require(FlowRunView.fold(parts: parts, turnState: nil, isActive: true))
        #expect(run.steps.map(\.status) == [.cancelled])
    }

    @Test func malformedDescriptorsAreIgnored() throws {
        let parts = [
            try runStarted(),
            // Two keys in one notification descriptor.
            try notice(#"{"phaseStarted": {"title": "Two"}, "phaseFinished": {"title": "Two"}}"#),
            // An unknown kind, a body that is not an object, a non-string title.
            try notice(#"{"phaseSkipped": {"title": "X"}}"#),
            try notice(#"{"phaseStarted": "Plan"}"#),
            try notice(#"{"phaseStarted": {"title": 7}}"#),
            // A run status outside ok/error.
            try notice(#"{"runFinished": {"status": "cancelled"}}"#),
            // The descriptor itself not an object.
            try notice(#""runStarted""#),
            // Steps without stepStarted, without an integer ordinal, a boolean ordinal.
            try toolCall("bad1", descriptor: #"{"stepFinished": {"status": "ok"}}"#),
            try toolCall("bad2", descriptor: #"{"stepStarted": {"ordinal": "0", "phase": "Plan"}}"#),
            try toolCall("bad3", descriptor: #"{"stepStarted": {"ordinal": true, "phase": "Plan"}}"#),
            try toolCall("bad4", descriptor: #"{"stepStarted": {"ordinal": 1.5, "phase": "Plan"}}"#),
            // A step whose stepFinished has an unknown status reads as unfinished.
            try step("t0", status: "running", started: started(0, phase: nil),
                     finished: #"{"status": "weird", "usage": {"inputTokens": 9, "outputTokens": 9}}"#),
            // Usage counts that are not integers count as 0.
            try step("t1", started: started(1, phase: nil),
                     finished: #"{"status": "ok", "result": 1, "usage": {"inputTokens": "x", "outputTokens": 2}}"#),
            // A tool call state this build does not know still yields its step.
            try toolCall("t2", status: "teleporting", descriptor: #"{"stepStarted": \#(started(2, phase: nil))}"#),
        ]
        let run = try #require(FlowRunView.fold(parts: parts, turnState: nil, isActive: true))
        #expect(run.status == .running)
        #expect(run.phases.map(\.title) == [nil])
        #expect(run.steps.map(\.toolCallID) == ["t0", "t1", "t2"])
        #expect(run.steps.map(\.status) == [.running, .ok, .running])
        #expect(run.steps[1].usage == FlowUsage(inputTokens: 0, outputTokens: 2))
        #expect(run.usage == FlowUsage(inputTokens: 0, outputTokens: 2))
    }

    @Test func aStepWhosePhaseWasNeverAnnouncedGetsThatPhase() throws {
        let parts = [
            try runStarted(),
            try phaseStarted("Plan"),
            try step("t0", status: "running", started: started(0, phase: "Review")),
            try step("t1", status: "running", started: started(1, phase: nil)),
            try step("t2", status: "running", started: started(2)),
        ]
        let run = try #require(FlowRunView.fold(parts: parts, turnState: nil, isActive: true))
        #expect(run.phases.map(\.title) == ["Plan", "Review", nil])
        #expect(run.phases.map(\.status) == [.running, .running, .running])
        #expect(run.phases.map { $0.steps.map(\.ordinal) } == [[2], [0], [1]])
    }

    @Test func theLastWritePerOrdinalWins() throws {
        let parts = [
            try runStarted(),
            try step("t0", status: "running", started: started(0), awaiting: true),
            try step("t0", started: started(0), finished: finished()),
        ]
        let run = try #require(FlowRunView.fold(parts: parts, turnState: nil, isActive: true))
        #expect(run.steps.count == 1)
        #expect(run.steps[0].status == .ok)
        #expect(run.steps[0].awaiting == false)
    }

    @Test func aRedactedResultIsKeptAsSent() throws {
        // flow.redacted_step: result and error replaced by "[redacted]".
        let parts = [
            try runStarted(),
            try step("t0", started: started(0),
                     finished: finished("error", result: #""[redacted]""#, error: "[redacted]")),
        ]
        let run = try #require(FlowRunView.fold(parts: parts, turnState: .complete, isActive: false))
        #expect(run.steps[0].status == .error)
        #expect(run.steps[0].result == AnyCodable("[redacted]"))
        #expect(run.steps[0].error == "[redacted]")
        #expect(run.steps[0].usage == FlowUsage(inputTokens: 10, outputTokens: 5))
    }

    @Test func flowNotificationsAreRecognised() throws {
        #expect(FlowRunView.isFlowNotification(try runStarted()))
        #expect(FlowRunView.isFlowNotification(try phaseFinished("Plan")))
        #expect(!FlowRunView.isFlowNotification(try part(#"{"kind": "systemNotification", "content": "log"}"#)))
        #expect(!FlowRunView.isFlowNotification(try part(
            #"{"kind": "systemNotification", "content": "x", "_meta": {"ahp-py/restart": {"event": "inputWithdrawn"}}}"#
        )))
        #expect(!FlowRunView.isFlowNotification(try step("t0", started: started(0))))
    }
}
