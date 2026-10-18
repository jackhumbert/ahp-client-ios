import AgentHostProtocol

/// The call a delegated session was started by: the session, chat and tool
/// call on whose behalf it runs, possibly on another host.
///
/// An ahp-py extension ahead of the spec. The protocol keeps an origin of an
/// unknown kind verbatim as `.unknown`, so it is read here, not in the package.
struct DelegationOrigin: Equatable {
    /// `SessionOrigin.kind` that ahp-py gives a delegated session.
    static let kind = "ahp-py/delegation"

    let session: String
    let chat: String
    let toolCallID: String

    /// The delegation in `origin`, or nil for no origin, another kind (such as
    /// `automation`), or a missing or empty field.
    init?(_ origin: SessionOrigin?) {
        guard case .unknown(let raw)? = origin,
              raw.stringField("kind") == Self.kind,
              let session = raw.stringField("session"), !session.isEmpty,
              let chat = raw.stringField("chat"), !chat.isEmpty,
              let toolCallID = raw.stringField("toolCallId"), !toolCallID.isEmpty
        else { return nil }
        self.session = session
        self.chat = chat
        self.toolCallID = toolCallID
    }
}
