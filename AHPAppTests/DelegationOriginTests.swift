import AgentHostProtocol
import Foundation
import Testing
@testable import AHPApp

/// Which session origins are an ahp-py delegation, read from the wire JSON
/// the protocol decodes into `SessionOrigin`.
@MainActor
struct DelegationOriginTests {
    private func origin(_ json: String) throws -> SessionOrigin {
        try JSONDecoder().decode(SessionOrigin.self, from: Data(json.utf8))
    }

    private let delegation = """
    {"kind": "ahp-py/delegation", "session": "ahp-session:/parent",
     "chat": "ahp-chat:/parent/main", "toolCallId": "call-7"}
    """

    @Test func delegationOriginParses() throws {
        let parsed = try #require(DelegationOrigin(origin(delegation)))
        #expect(parsed.session == "ahp-session:/parent")
        #expect(parsed.chat == "ahp-chat:/parent/main")
        #expect(parsed.toolCallID == "call-7")
    }

    @Test func extraFieldsAreIgnored() throws {
        let json = """
        {"kind": "ahp-py/delegation", "session": "s", "chat": "c",
         "toolCallId": "t", "host": "elsewhere"}
        """
        let parsed = try #require(DelegationOrigin(origin(json)))
        #expect(parsed.toolCallID == "t")
    }

    @Test func automationOriginIsNotADelegation() throws {
        let json = """
        {"kind": "automation", "automation": "ahp-automation:/a", "run": "ahp-run:/r"}
        """
        #expect(DelegationOrigin(try origin(json)) == nil)
    }

    @Test func unknownKindIsNotADelegation() throws {
        let json = """
        {"kind": "ahp-py/other", "session": "s", "chat": "c", "toolCallId": "t"}
        """
        #expect(DelegationOrigin(try origin(json)) == nil)
    }

    @Test func noOriginIsNotADelegation() {
        #expect(DelegationOrigin(nil) == nil)
    }

    @Test func missingFieldIsNotADelegation() throws {
        for field in ["session", "chat", "toolCallId"] {
            var object = try JSONSerialization.jsonObject(
                with: Data(delegation.utf8)
            ) as? [String: Any] ?? [:]
            object[field] = nil
            let data = try JSONSerialization.data(withJSONObject: object)
            let decoded = try JSONDecoder().decode(SessionOrigin.self, from: data)
            #expect(DelegationOrigin(decoded) == nil, "missing \(field)")
        }
    }

    @Test func emptyFieldIsNotADelegation() throws {
        for field in ["session", "chat", "toolCallId"] {
            var object = try JSONSerialization.jsonObject(
                with: Data(delegation.utf8)
            ) as? [String: Any] ?? [:]
            object[field] = ""
            let data = try JSONSerialization.data(withJSONObject: object)
            let decoded = try JSONDecoder().decode(SessionOrigin.self, from: data)
            #expect(DelegationOrigin(decoded) == nil, "empty \(field)")
        }
    }

    // MARK: Queries over session summaries

    private func summary(
        _ resource: String, modifiedAt: String, parent: String? = nil,
        chat: String = "chat-1", call: String = "call-1"
    ) throws -> SessionSummary {
        var origin: SessionOrigin?
        if let parent {
            origin = try self.origin("""
            {"kind": "ahp-py/delegation", "session": "\(parent)",
             "chat": "\(chat)", "toolCallId": "\(call)"}
            """)
        }
        return SessionSummary(
            provider: "copilot", title: resource, status: .idle, origin: origin,
            resource: resource, createdAt: modifiedAt, modifiedAt: modifiedAt
        )
    }

    @Test func listedParentNestsItsChildren() throws {
        let all = [
            try summary("child-old", modifiedAt: "2026-01-01T00:00:01.000Z", parent: "parent"),
            try summary("parent", modifiedAt: "2026-01-01T00:00:00.000Z"),
            try summary("child-new", modifiedAt: "2026-01-01T00:00:02.000Z", parent: "parent"),
            try summary("other", modifiedAt: "2026-01-01T00:00:03.000Z"),
        ]
        #expect(AppStore.delegatedSessions(of: "parent", in: all).map(\.resource)
                == ["child-new", "child-old"])
        #expect(AppStore.delegatedSessions(of: "other", in: all).isEmpty)
        #expect(Set(AppStore.topLevel(all).map(\.resource)) == ["parent", "other"])
    }

    @Test func missingParentLeavesChildTopLevel() throws {
        let all = [
            try summary("orphan", modifiedAt: "2026-01-01T00:00:00.000Z", parent: "gone"),
            try summary("plain", modifiedAt: "2026-01-01T00:00:01.000Z"),
        ]
        #expect(Set(AppStore.topLevel(all).map(\.resource)) == ["orphan", "plain"])
    }

    @Test func toolCallLookupMatchesCallAndChat() throws {
        let all = [
            try summary("a", modifiedAt: "2026-01-01T00:00:00.000Z", parent: "p",
                        chat: "chat-1", call: "call-1"),
            try summary("b", modifiedAt: "2026-01-01T00:00:01.000Z", parent: "p",
                        chat: "chat-2", call: "call-1"),
            try summary("c", modifiedAt: "2026-01-01T00:00:02.000Z", parent: "p",
                        chat: "chat-1", call: "call-2"),
            try summary("d", modifiedAt: "2026-01-01T00:00:03.000Z", parent: "p",
                        chat: "chat-1", call: "call-1"),
        ]
        #expect(AppStore.delegatedSessions(forToolCall: "call-1", inChat: "chat-1", in: all)
                .map(\.resource) == ["d", "a"])
        #expect(AppStore.delegatedSessions(forToolCall: "call-9", inChat: "chat-1", in: all).isEmpty)
    }
}
