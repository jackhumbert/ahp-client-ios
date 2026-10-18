import AgentHostProtocol
import Foundation

/// Typed progress for a workflow run, folded from one turn's response parts.
///
/// An ahp-py workflow host narrates a run as ordinary content: a
/// `systemNotification` part for the run and each phase, and one `toolCall`
/// per step. Each carries a small descriptor under `_meta["ahp-py/flow"]`
/// (`ahp_protocol/ext/flow.py` in ahp-py, schema `flow.schema.json` beside
/// it). This is a port of that module's fold (`_fold_turn`), status rules
/// included, so the app shows a run exactly as ahp-py's own client would.
///
/// The parts are data written by a peer: anything malformed is skipped, never
/// an error.
struct FlowRunView: Equatable, Sendable {
    enum Status: String, Sendable {
        case running, ok, error, cancelled
    }

    let runID: String?
    let workflow: String?
    let status: Status
    /// The `runFinished` error, if the run said why it failed.
    let error: String?
    /// In the order a phase was first mentioned, by a `phaseStarted`, a
    /// `phaseFinished` or a step naming it. Steps without a phase gather under
    /// a phase whose title is nil.
    let phases: [FlowPhaseView]
    /// The sum over every finished step's usage.
    let usage: FlowUsage

    /// Every step of every phase, by ordinal.
    var steps: [FlowStepView] {
        phases.flatMap(\.steps).sorted { $0.ordinal < $1.ordinal }
    }
}

struct FlowPhaseView: Equatable, Sendable {
    enum Status: String, Sendable {
        case running, finished
    }

    let title: String?
    let status: Status
    let steps: [FlowStepView]
}

struct FlowStepView: Equatable, Sendable {
    /// `running` and `cancelled` are the fold's; the rest are
    /// `stepFinished.status` (`null` is a step that returned nothing).
    enum Status: String, Sendable {
        case running, cancelled, ok, null, error, skipped
    }

    let toolCallID: String
    let ordinal: Int
    let label: String?
    let phase: String?
    /// The worker chat the step ran in, if it had one.
    let chat: String?
    let model: String?
    let provider: String?
    let status: Status
    /// The step's result as the host sent it; a host may redact it to the
    /// string `"[redacted]"`.
    let result: AnyCodable?
    let usage: FlowUsage?
    let error: String?
    /// Blocked on the user (an input request or approval); only while running.
    let awaiting: Bool
}

struct FlowUsage: Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int

    static let zero = FlowUsage(inputTokens: 0, outputTokens: 0)
}

extension FlowRunView {
    /// The `_meta` key every descriptor sits under.
    static let metaKey = "ahp-py/flow"

    /// True for a run or phase notice: a `systemNotification` part with a
    /// flow descriptor. A header that shows the run can hide these.
    static func isFlowNotification(_ part: ResponsePart) -> Bool {
        guard case .systemNotification(let notice) = part else { return false }
        return notice.meta?[metaKey]?.value is [String: Any]
    }

    /// The run in a turn's parts, or nil when they hold no `runStarted`.
    ///
    /// `turnState` is how a finished turn ended (nil while it runs);
    /// `isActive` is true for the chat's active turn.
    static func fold(parts: [ResponsePart], turnState: TurnState?, isActive: Bool) -> FlowRunView? {
        var isRun = false
        var runID: String?
        var workflow: String?
        var finishedStatus: Status?
        var finishedError: String?
        var phaseOrder: [String?] = []
        var finishedPhases: Set<String> = []
        var raws: [Int: RawStep] = [:]

        func notePhase(_ title: String?) {
            if !phaseOrder.contains(title) { phaseOrder.append(title) }
        }

        for part in parts {
            switch part {
            case .systemNotification(let notice):
                guard let descriptor = notice.meta?[metaKey]?.value as? [String: Any],
                      descriptor.count == 1,
                      let entry = descriptor.first,
                      let body = entry.value as? [String: Any]
                else { continue }
                let name = entry.key
                let title = body.stringField("title")
                switch name {
                case "runStarted":
                    isRun = true
                    runID = body.stringField("runId")
                    workflow = body.stringField("workflow")
                case "phaseStarted":
                    if let title {
                        notePhase(title)
                        finishedPhases.remove(title)
                    }
                case "phaseFinished":
                    if let title {
                        notePhase(title)
                        finishedPhases.insert(title)
                    }
                case "runFinished":
                    switch body.stringField("status") {
                    case "ok": finishedStatus = .ok
                    case "error": finishedStatus = .error
                    default: continue
                    }
                    finishedError = body.stringField("error")
                default:
                    continue
                }
            case .toolCall(let call):
                let toolCall = ToolCallFields(call.toolCall)
                guard let descriptor = toolCall.meta?[metaKey]?.value as? [String: Any],
                      let started = descriptor.dictField("stepStarted"),
                      let ordinal = started.intField("ordinal")
                else { continue }
                // Last write per ordinal wins.
                raws[ordinal] = RawStep(
                    started: started,
                    finished: descriptor.dictField("stepFinished"),
                    awaiting: descriptor.boolField("awaitingInput") == true,
                    toolCallID: toolCall.id,
                    isCancelled: toolCall.isCancelled
                )
                notePhase(started.stringField("phase"))
            default:
                continue
            }
        }

        guard isRun else { return nil }
        let status: Status
        if let finishedStatus {
            status = finishedStatus
        } else if isActive {
            status = .running
        } else if turnState == .cancelled {
            status = .cancelled
        } else if turnState == .error {
            status = .error
        } else {
            status = .ok
        }

        var byPhase: [String?: [FlowStepView]] = [:]
        var total = FlowUsage.zero
        for ordinal in raws.keys.sorted() {
            guard let raw = raws[ordinal] else { continue }
            var stepStatus: FlowStepView.Status
            var result: AnyCodable?
            var usage: FlowUsage?
            var error: String?
            if let finished = raw.finished,
               let finishedStatus = finished.stringField("status").flatMap(FlowStepView.Status.init(rawValue:)),
               finishedStatus != .running, finishedStatus != .cancelled {
                stepStatus = finishedStatus
                // JSON null reads as nil, as in flow.py.
                result = finished["result"].flatMap { $0 is NSNull ? nil : AnyCodable($0) }
                error = finished.stringField("error")
                if let rawUsage = finished.dictField("usage") {
                    let counted = FlowUsage(
                        // Anything but an integer counts as 0.
                        inputTokens: rawUsage.intField("inputTokens") ?? 0,
                        outputTokens: rawUsage.intField("outputTokens") ?? 0
                    )
                    usage = counted
                    total.inputTokens += counted.inputTokens
                    total.outputTokens += counted.outputTokens
                }
            } else if raw.isCancelled || status != .running {
                stepStatus = .cancelled
            } else {
                stepStatus = .running
            }
            let phase = raw.started.stringField("phase")
            byPhase[phase, default: []].append(FlowStepView(
                toolCallID: raw.toolCallID,
                ordinal: ordinal,
                label: raw.started.stringField("label"),
                phase: phase,
                chat: raw.started.stringField("chat"),
                model: raw.started.stringField("model"),
                provider: raw.started.stringField("provider"),
                status: stepStatus,
                result: result,
                usage: usage,
                error: error,
                awaiting: raw.awaiting && stepStatus == .running
            ))
        }

        let phases = phaseOrder.map { title in
            let finished = status != .running || title.map { finishedPhases.contains($0) } == true
            return FlowPhaseView(
                title: title,
                status: finished ? .finished : .running,
                steps: byPhase[title] ?? []
            )
        }
        return FlowRunView(
            runID: runID,
            workflow: workflow,
            status: status,
            error: finishedError,
            phases: phases,
            usage: total
        )
    }
}

/// What one step's latest part said, before the run's status is known.
private struct RawStep {
    let started: [String: Any]
    let finished: [String: Any]?
    let awaiting: Bool
    let toolCallID: String
    let isCancelled: Bool
}

/// The fields the fold reads from a tool call in any state. A state this
/// build does not know is read from its raw object, since `baseFields`
/// traps on `.unknown`.
private struct ToolCallFields {
    let id: String
    let meta: [String: AnyCodable]?
    let isCancelled: Bool

    init(_ state: ToolCallState) {
        switch state {
        case .unknown(let raw):
            id = raw.stringField("toolCallId") ?? ""
            meta = raw.dictField("_meta")?.mapValues(AnyCodable.init)
            isCancelled = raw.stringField("status") == "cancelled"
        default:
            let base = state.baseFields
            id = base.toolCallId
            meta = base.meta
            if case .cancelled = state { isCancelled = true } else { isCancelled = false }
        }
    }
}
