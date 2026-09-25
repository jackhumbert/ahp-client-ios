import AgentHostProtocol
import SwiftUI

/// How tool calls appear in a chat (Settings → Tool Calls).
enum ToolCallStyle: String, CaseIterable, Identifiable {
    /// A card per call: message, command, status, buttons.
    case cards
    /// One line per call: icon, what it did, status.
    case compact
    /// Each run of consecutive calls folds into one row that expands to
    /// compact lines.
    case collapsed

    var id: String { rawValue }

    static let storageKey = "toolCallStyle"

    var title: String {
        switch self {
        case .cards: "Cards"
        case .compact: "Compact"
        case .collapsed: "Collapsed"
        }
    }

    var summary: String {
        switch self {
        case .cards: "Each call as a card with its message and command."
        case .compact: "Each call on one line; tap it for details."
        case .collapsed: "Consecutive calls fold into one row; tap to expand."
        }
    }
}

extension ToolCallState {
    /// Waiting on the user: always drawn as a full card, never folded away.
    var needsUser: Bool {
        switch self {
        case .pendingConfirmation, .pendingResultConfirmation, .authRequired: true
        default: false
        }
    }

    var isInProgress: Bool {
        switch self {
        case .streaming, .running: true
        default: false
        }
    }

    var failed: Bool {
        if case .completed(let s) = self { return !s.success }
        return false
    }
}

/// A turn's response parts, with runs of tool calls grouped for the
/// collapsed style.
enum ResponseSegment: Identifiable {
    case part(Int, ResponsePart)
    /// Two or more consecutive tool calls, none waiting on the user.
    case toolCalls(Int, [ToolCallState])

    var id: Int {
        switch self {
        case .part(let i, _), .toolCalls(let i, _): i
        }
    }

    static func make(_ parts: [ResponsePart], style: ToolCallStyle) -> [ResponseSegment] {
        guard style == .collapsed else {
            return parts.enumerated().map { .part($0.offset, $0.element) }
        }
        var segments: [ResponseSegment] = []
        var run: [(Int, ResponsePart, ToolCallState)] = []

        func flush() {
            if run.count >= 2 {
                segments.append(.toolCalls(run[0].0, run.map(\.2)))
            } else {
                segments += run.map { .part($0.0, $0.1) }
            }
            run = []
        }

        for (index, part) in parts.enumerated() {
            if case .toolCall(let tc) = part, !tc.toolCall.needsUser {
                run.append((index, part, tc.toolCall))
            } else {
                flush()
                segments.append(.part(index, part))
            }
        }
        flush()
        return segments
    }
}

/// Response parts in the chosen tool-call style.
struct ResponsePartsView: View {
    let parts: [ResponsePart]
    @AppStorage(ToolCallStyle.storageKey) private var style: ToolCallStyle = .cards

    var body: some View {
        ForEach(ResponseSegment.make(parts, style: style)) { segment in
            switch segment {
            case .part(_, let part):
                ResponsePartView(part: part)
            case .toolCalls(_, let calls):
                ToolCallGroupView(calls: calls)
            }
        }
    }
}

/// A run of tool calls folded into one row: how many, and how they went.
struct ToolCallGroupView: View {
    let calls: [ToolCallState]
    @State private var isExpanded = false

    private var running: Int { calls.filter(\.isInProgress).count }
    private var failed: Int { calls.filter(\.failed).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(.secondary)
                    Text("\(calls.count) tool calls")
                        .font(.subheadline.weight(.medium))
                    if failed > 0 {
                        Text("\(failed) failed")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer(minLength: 8)
                    if running > 0 {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: failed > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(failed > 0 ? .red : .green)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(calls.enumerated()), id: \.offset) { _, call in
                        ToolCallPartView(toolCall: call, forceCompact: true)
                    }
                }
                .padding(.leading, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.6))
        )
    }
}

/// Settings → Tool Calls.
struct ToolCallStyleSettings: View {
    @AppStorage(ToolCallStyle.storageKey) private var style: ToolCallStyle = .cards

    var body: some View {
        List {
            Section {
                ForEach(ToolCallStyle.allCases) { option in
                    Button {
                        style = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                Text(option.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option == style {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("A call waiting for your approval or an answer always shows as a full card.")
            }
        }
        .navigationTitle("Tool Calls")
        .navigationBarTitleDisplayMode(.inline)
    }
}
