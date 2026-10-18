import AgentHostProtocol
import Foundation
import Testing
@testable import AHPApp

/// Per-chat config (AHP 1.1.0): which value a chat sees, and where a change
/// to a property is written.
@MainActor
struct ChatConfigTests {
    static func schema(
        sessionMutable: Bool? = nil,
        chatMutable: Bool? = nil,
        readOnly: Bool? = nil
    ) -> SessionConfigPropertySchema {
        SessionConfigPropertySchema(
            type: "string",
            title: "Mode",
            readOnly: readOnly,
            sessionMutable: sessionMutable,
            chatMutable: chatMutable
        )
    }

    @Test func chatValueOverridesSession() {
        let value = AppStore.effectiveConfigValue(
            "mode",
            chatValues: ["mode": AnyCodable("chat")],
            sessionValues: ["mode": AnyCodable("session")]
        )
        #expect(value == AnyCodable("chat"))
    }

    @Test func fallsBackToSession() {
        let value = AppStore.effectiveConfigValue(
            "mode",
            chatValues: ["other": AnyCodable("x")],
            sessionValues: ["mode": AnyCodable("session")]
        )
        #expect(value == AnyCodable("session"))
        #expect(AppStore.effectiveConfigValue(
            "mode", chatValues: nil, sessionValues: ["mode": AnyCodable("session")]
        ) == AnyCodable("session"))
    }

    @Test func missingEverywhereIsNil() {
        #expect(AppStore.effectiveConfigValue("mode", chatValues: [:], sessionValues: [:]) == nil)
        #expect(AppStore.effectiveConfigValue("mode", chatValues: nil, sessionValues: nil) == nil)
    }

    @Test func writeTargetFollowsMutability() {
        typealias S = ChatConfigTests
        #expect(AppStore.configWriteTarget(for: nil) == .none)
        #expect(AppStore.configWriteTarget(for: S.schema()) == .none)
        #expect(AppStore.configWriteTarget(for: S.schema(sessionMutable: true)) == .session)
        #expect(AppStore.configWriteTarget(for: S.schema(chatMutable: true)) == .chat)
        #expect(AppStore.configWriteTarget(for: S.schema(sessionMutable: true, chatMutable: true)) == .chat)
        #expect(AppStore.configWriteTarget(for: S.schema(sessionMutable: false, chatMutable: false)) == .none)
    }

    @Test func readOnlyIsNeverWritten() {
        typealias S = ChatConfigTests
        #expect(AppStore.configWriteTarget(for: S.schema(sessionMutable: true, readOnly: true)) == .none)
        #expect(AppStore.configWriteTarget(for: S.schema(chatMutable: true, readOnly: true)) == .none)
        #expect(AppStore.configWriteTarget(for: S.schema(sessionMutable: true, chatMutable: true, readOnly: true)) == .none)
    }
}
