import Foundation

/// Protocol timestamps.
///
/// Since spec 0.9.0 every timestamp on the wire (`createdAt`, `modifiedAt`,
/// `startedAt`) is an ISO 8601 string with milliseconds, e.g.
/// `"2025-03-10T18:42:03.123Z"` (`types/session-state.ts`). Upstream's app
/// predates that and compared them as millisecond integers.
enum AHPTimestamp {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The wire form of `date`.
    static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    /// Parses a wire timestamp. The spec's example carries milliseconds, but a
    /// peer that omits them is still sending valid ISO 8601, so accept both.
    static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? withoutFraction.date(from: string)
    }
}
