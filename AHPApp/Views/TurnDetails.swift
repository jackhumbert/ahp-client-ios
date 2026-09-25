import AgentHostProtocol
import SwiftUI

/// One piece of information the line under an agent's reply can show.
enum TurnDetail: String, CaseIterable, Identifiable {
    case time
    case duration
    case model
    case toolCalls
    case inputTokens
    case outputTokens
    case cachedTokens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: "Time received"
        case .duration: "Duration"
        case .model: "Model"
        case .toolCalls: "Tool calls"
        case .inputTokens: "Input tokens"
        case .outputTokens: "Output tokens"
        case .cachedTokens: "Cached tokens"
        }
    }

    var systemImage: String {
        switch self {
        case .time: "clock"
        case .duration: "timer"
        case .model: "cpu"
        case .toolCalls: "wrench.and.screwdriver"
        case .inputTokens: "arrow.down.circle"
        case .outputTokens: "arrow.up.circle"
        case .cachedTokens: "memorychip"
        }
    }

    /// The `@AppStorage` key holding the chosen details, in display order.
    static let storageKey = "turnDetails"
    /// Time received only, until someone chooses otherwise.
    static let defaultValue = TurnDetail.time.rawValue

    static func decode(_ stored: String) -> [TurnDetail] {
        stored.split(separator: ",").compactMap { TurnDetail(rawValue: String($0)) }
    }

    static func encode(_ details: [TurnDetail]) -> String {
        details.map(\.rawValue).joined(separator: ",")
    }
}

/// What a turn knows about itself, for the detail line.
struct TurnFacts {
    var startedAt: String?
    /// Nil while the turn is still running.
    var durationMs: Int?
    var usage: UsageInfo?
    var toolCalls: Int

    /// When the reply finished: start plus duration.
    var receivedAt: Date? {
        guard let startedAt, let durationMs, let start = Self.parse(startedAt) else { return nil }
        return start.addingTimeInterval(Double(durationMs) / 1000)
    }

    private static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// The text for `detail`, or nil when this turn doesn't have it.
    func text(for detail: TurnDetail, now: Date = Date()) -> String? {
        switch detail {
        case .time:
            guard let receivedAt else { return nil }
            let calendar = Calendar.current
            if calendar.isDate(receivedAt, inSameDayAs: now) {
                return receivedAt.formatted(date: .omitted, time: .shortened)
            }
            return receivedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        case .duration:
            guard let durationMs else { return nil }
            let seconds = Double(durationMs) / 1000
            if seconds < 10 { return String(format: "%.1fs", seconds) }
            let whole = Int(seconds.rounded())
            return whole < 60 ? "\(whole)s" : "\(whole / 60)m \(whole % 60)s"
        case .model:
            return usage?.model
        case .toolCalls:
            return toolCalls > 0 ? (toolCalls == 1 ? "1 tool call" : "\(toolCalls) tool calls") : nil
        case .inputTokens:
            return usage?.inputTokens.map { "\(Self.count($0)) in" }
        case .outputTokens:
            return usage?.outputTokens.map { "\(Self.count($0)) out" }
        case .cachedTokens:
            return usage?.cacheReadTokens.map { "\(Self.count($0)) cached" }
        }
    }

    /// 1,448 and 12.3k: exact while short, compact once long.
    private static func count(_ n: Int) -> String {
        n < 10_000 ? n.formatted() : (Double(n) / 1000).formatted(.number.precision(.fractionLength(1))) + "k"
    }
}

extension TurnFacts {
    init(_ turn: Turn) {
        self.init(
            startedAt: turn.startedAt,
            durationMs: turn.duration,
            usage: turn.usage,
            toolCalls: turn.responseParts.filter { if case .toolCall = $0 { true } else { false } }.count
        )
    }

    init(_ turn: ActiveTurn) {
        self.init(
            startedAt: turn.startedAt,
            durationMs: nil,
            usage: turn.usage,
            toolCalls: turn.responseParts.filter { if case .toolCall = $0 { true } else { false } }.count
        )
    }
}

/// The line under an agent's reply: whichever details the user chose
/// (Settings → Reply details), in their order, skipping any this turn lacks.
struct TurnDetailsLine: View {
    let facts: TurnFacts
    @AppStorage(TurnDetail.storageKey) private var stored = TurnDetail.defaultValue

    var body: some View {
        let shown = TurnDetail.decode(stored).compactMap { detail in
            facts.text(for: detail).map { (detail, $0) }
        }
        if !shown.isEmpty {
            HStack(spacing: 10) {
                ForEach(shown, id: \.0) { detail, text in
                    Label(text, systemImage: detail.systemImage)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            // The same left edge as reply text.
            .padding(.leading, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Settings → Reply details: which details show, and in what order.
struct TurnDetailsSettings: View {
    @AppStorage(TurnDetail.storageKey) private var stored = TurnDetail.defaultValue

    private var chosen: [TurnDetail] { TurnDetail.decode(stored) }

    var body: some View {
        List {
            Section {
                ForEach(chosen) { detail in
                    Label(detail.title, systemImage: detail.systemImage)
                }
                .onMove { from, to in
                    var details = chosen
                    details.move(fromOffsets: from, toOffset: to)
                    stored = TurnDetail.encode(details)
                }
                .onDelete { offsets in
                    var details = chosen
                    details.remove(atOffsets: offsets)
                    stored = TurnDetail.encode(details)
                }
            } header: {
                Text("Shown")
            } footer: {
                Text(chosen.isEmpty ? "Nothing is shown under replies." : "Drag to reorder; tap − to hide.")
            }

            let hidden = TurnDetail.allCases.filter { !chosen.contains($0) }
            if !hidden.isEmpty {
                Section("Hidden") {
                    ForEach(hidden) { detail in
                        Button {
                            stored = TurnDetail.encode(chosen + [detail])
                        } label: {
                            Label {
                                Text(detail.title)
                            } icon: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        // A row moving between sections comes in without its edit controls
        // unless the list is rebuilt.
        .id(stored)
        .navigationTitle("Reply Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
