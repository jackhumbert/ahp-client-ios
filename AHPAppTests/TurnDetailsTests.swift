import AgentHostProtocol
import Foundation
import Testing
@testable import AHPApp

struct TurnDetailsTests {
    let facts = TurnFacts(
        startedAt: "2026-09-24T20:00:00.000Z",
        durationMs: 12_400,
        usage: UsageInfo(inputTokens: 1_448, outputTokens: 23_456, model: "claude-opus", cacheReadTokens: 900),
        toolCalls: 3
    )

    @Test func eachDetailHasText() {
        #expect(facts.text(for: .duration) == "12s")
        #expect(facts.text(for: .model) == "claude-opus")
        #expect(facts.text(for: .toolCalls) == "3 tool calls")
        #expect(facts.text(for: .inputTokens) == "1,448 in")
        #expect(facts.text(for: .outputTokens) == "23.5k out")
        #expect(facts.text(for: .cachedTokens) == "900 cached")
    }

    @Test func receivedIsStartPlusDuration() {
        let expected = ISO8601DateFormatter().date(from: "2026-09-24T20:00:12Z")!
        #expect(abs(facts.receivedAt!.timeIntervalSince(expected) - 0.4) < 0.01)
        #expect(facts.text(for: .time, now: expected) == facts.receivedAt!.formatted(date: .omitted, time: .shortened))
    }

    @Test func aRunningTurnHasNoTimeOrDuration() {
        let running = TurnFacts(startedAt: "2026-09-24T20:00:00Z", durationMs: nil, usage: nil, toolCalls: 0)
        #expect(running.text(for: .time) == nil)
        #expect(running.text(for: .duration) == nil)
        #expect(running.text(for: .toolCalls) == nil)
    }

    @Test func storedChoicesKeepOrderAndDropUnknowns() {
        #expect(TurnDetail.decode("model,time,bogus") == [.model, .time])
        #expect(TurnDetail.encode([.time, .outputTokens]) == "time,outputTokens")
    }
}
