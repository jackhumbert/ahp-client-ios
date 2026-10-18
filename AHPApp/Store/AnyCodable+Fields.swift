import AgentHostProtocol
import Foundation

/// Typed reads of JSON object fields.
///
/// The protocol's open unions decode a variant this build does not know as
/// `.unknown(AnyCodable)`, preserving the raw object, and `_meta` bags are
/// plain JSON. These helpers read one field without casting at every call
/// site. JSON `null` decodes as `NSNull` and reads as `nil`, as does a value of
/// another type. Numbers follow JSON: `3.0` is the integer `3`, `3.5` is not an
/// integer, and a boolean is never a number.
extension AnyCodable {
    /// A string field of a JSON object payload.
    ///
    /// The common fields (`id`, `title`, `message`) of an unknown variant are
    /// still worth showing.
    func stringField(_ key: String) -> String? {
        (value as? [String: Any])?.stringField(key)
    }

    func dictField(_ key: String) -> [String: Any]? {
        (value as? [String: Any])?.dictField(key)
    }

    func intField(_ key: String) -> Int? {
        (value as? [String: Any])?.intField(key)
    }

    func boolField(_ key: String) -> Bool? {
        (value as? [String: Any])?.boolField(key)
    }

    func arrayField(_ key: String) -> [Any]? {
        (value as? [String: Any])?.arrayField(key)
    }
}

/// The same reads over a decoded JSON object, so a nested object reads like
/// the top level: `meta.dictField("ahp-py/flow")?.intField("ordinal")`.
extension Dictionary where Key == String, Value == Any {
    func stringField(_ key: String) -> String? {
        self[key] as? String
    }

    func dictField(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func intField(_ key: String) -> Int? {
        guard let value = self[key], !isBoolean(value) else { return nil }
        // Double first: a boxed NSNumber 3.5 must not truncate to 3 on the way
        // to Int. A native Int is never cast to Double, so it falls through.
        if let double = value as? Double {
            return Int(exactly: double)
        }
        return value as? Int
    }

    func boolField(_ key: String) -> Bool? {
        guard let value = self[key], isBoolean(value) else { return nil }
        return value as? Bool
    }

    func arrayField(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }
}

/// True for a JSON boolean, native or bridged from `JSONSerialization`.
/// `NSNumber(value: 1)` is a number, so the check is on the boolean type and
/// not on whether the value bridges to `Bool`.
private func isBoolean(_ value: Any) -> Bool {
    if type(of: value) == Bool.self { return true }
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}
