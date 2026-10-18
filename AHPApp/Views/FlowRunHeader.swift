import AgentHostProtocol
import SwiftUI

/// A workflow run's progress at the top of its turn: the run's status, each
/// phase with its step count, and the steps of the phase the user opens. A step
/// that ran in a worker chat the session lists opens that chat.
struct FlowRunHeader: View {
    let run: FlowRunView
    @Environment(AppStore.self) private var store
    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.secondary)
                Text(run.workflow ?? "Workflow")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Label(runStatusText, systemImage: runStatusIcon)
                    .font(.caption)
                    .foregroundStyle(runStatusColor)
            }
            if let error = run.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(Array(run.phases.enumerated()), id: \.offset) { index, phase in
                phaseView(phase, index: index)
            }
            if run.usage != .zero {
                Text("\(run.usage.inputTokens.formatted()) in, \(run.usage.outputTokens.formatted()) out tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Phases

    private func phaseView(_ phase: FlowPhaseView, index: Int) -> some View {
        let isOpen = expanded.contains(index)
        let finished = phase.steps.filter { $0.status != .running }.count
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if isOpen { expanded.remove(index) } else { expanded.insert(index) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Image(systemName: phase.status == .finished ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.caption)
                        .foregroundStyle(phase.status == .finished ? Color.green : Color.accentColor)
                    Text(phase.title ?? "Steps")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text("\(finished)/\(phase.steps.count) steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(phase.steps, id: \.toolCallID) { step in
                        stepView(step)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    // MARK: Steps

    private func canOpen(_ step: FlowStepView) -> Bool {
        guard let chat = step.chat, !chat.isEmpty else { return false }
        return store.currentSession?.chats.contains { $0.resource == chat } == true
    }

    @ViewBuilder
    private func stepView(_ step: FlowStepView) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            stepButton(step)
            DelegatedSessionRows(toolCallID: step.toolCallID)
                .padding(.leading, 20)
        }
    }

    @ViewBuilder
    private func stepButton(_ step: FlowStepView) -> some View {
        let openable = canOpen(step)
        Button {
            if openable { store.selectChat(step.chat) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Self.icon(for: step.status))
                    .font(.caption)
                    .foregroundStyle(Self.color(for: step.status))
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.label ?? "Step \(step.ordinal)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let model = step.model, !model.isEmpty {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if step.awaiting {
                        Text("Waiting for you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                if openable {
                    Text("Open")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!openable)
        .accessibilityHint(openable ? "Opens the step's chat" : "")
    }

    private static func icon(for status: FlowStepView.Status) -> String {
        switch status {
        case .running: "circle.dotted"
        case .ok: "checkmark.circle.fill"
        case .null: "minus.circle"
        case .error: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        case .skipped: "arrow.right.circle"
        }
    }

    private static func color(for status: FlowStepView.Status) -> Color {
        switch status {
        case .running: .accentColor
        case .ok: .green
        case .error: .red
        case .null, .cancelled, .skipped: .secondary
        }
    }

    // MARK: Run status

    private var runStatusText: String {
        switch run.status {
        case .running: "Running"
        case .ok: "Finished"
        case .error: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    private var runStatusIcon: String {
        switch run.status {
        case .running: "circle.dotted"
        case .ok: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }

    private var runStatusColor: Color {
        switch run.status {
        case .running: .accentColor
        case .ok: .green
        case .error: .red
        case .cancelled: .secondary
        }
    }
}

#Preview("Flow run", traits: .fixedLayout(width: 390, height: 420)) {
    FlowRunHeader(run: FlowRunView(
        runID: "run-1",
        workflow: "build-to-spec",
        status: .running,
        error: nil,
        phases: [
            FlowPhaseView(title: "Implement", status: .finished, steps: [
                FlowStepView(
                    toolCallID: "t1", ordinal: 0, label: "Write the view", phase: "Implement",
                    chat: nil, model: "claude-sonnet", provider: nil, status: .ok,
                    result: nil, usage: FlowUsage(inputTokens: 1200, outputTokens: 340),
                    error: nil, awaiting: false
                ),
            ]),
            FlowPhaseView(title: "Review", status: .running, steps: [
                FlowStepView(
                    toolCallID: "t2", ordinal: 1, label: "Check the diff", phase: "Review",
                    chat: nil, model: "claude-opus", provider: nil, status: .running,
                    result: nil, usage: nil, error: nil, awaiting: true
                ),
            ]),
        ],
        usage: FlowUsage(inputTokens: 1200, outputTokens: 340)
    ))
    .environment(AppStore())
    .padding()
}
