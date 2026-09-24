import AgentHostProtocol

extension AnyCodable {
    /// A string field of a JSON object payload.
    ///
    /// The protocol's open unions decode a variant this build does not know as
    /// `.unknown(AnyCodable)`, preserving the raw object. The common fields
    /// (`id`, `title`, `message`) are still worth showing.
    func stringField(_ key: String) -> String? {
        (value as? [String: Any])?[key] as? String
    }
}
