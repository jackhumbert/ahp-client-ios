import Foundation

/// A link in a reply that points at a file on the host, resolved to that
/// file's URI and, when the link names one, a line.
///
/// Agents write links relative to the session's working folder —
/// `[README](README.md)`, `[foo.swift:42](src/foo.swift:42)`, `docs/a.md#L10`
/// — or as absolute paths. Resolving them against the working folder's URI
/// keeps the machine the session runs on, which a broker needs to route the
/// read (`file://<machine>/…` or `ahp-file://…`).
struct FileLink: Hashable, Identifiable {
    let uri: String
    let line: Int?

    var id: String { "\(uri)#\(line ?? 0)" }

    /// Schemes that belong to something other than the host's files.
    private static let externalSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms", "facetime", "maps"]

    /// The file `href` names, or nil for a web link or anything unresolvable.
    static func resolve(_ href: String, base: String?) -> FileLink? {
        let href = href.trimmingCharacters(in: .whitespaces)
        if let scheme = URL(string: href)?.scheme?.lowercased() {
            if externalSchemes.contains(scheme) { return nil }
            // A host URI already: open as it is.
            if scheme == "file" || scheme == FolderURI.brokerScheme {
                let (path, line) = splitLine(href)
                return FileLink(uri: path, line: line)
            }
            // Otherwise the "scheme" is a filename before a colon ("a.md:10").
        }
        guard let base, let baseURL = URL(string: base) else { return nil }
        var (path, line) = splitLine(href)
        path = path.removingPercentEncoding ?? path
        guard !path.isEmpty else { return nil }

        let isWindowsDrive = path.count >= 2 && path.dropFirst().first == ":" && path.first!.isLetter
        if path.hasPrefix("/") || isWindowsDrive {
            // Absolute: same machine, path outside any root.
            let absolute = isWindowsDrive ? "/" + path : path
            return FileLink(uri: onSameMachine(baseURL, absolutePath: absolute), line: line)
        }

        var segments = FolderURI.path(base).split(separator: "/").map(String.init)
        for part in path.split(separator: "/").map(String.init) {
            switch part {
            case "", ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(part)
            }
        }
        return FileLink(uri: rebuild(baseURL, pathSegments: segments), line: line)
    }

    /// `a.swift:42`, `a.swift:42:7`, `a.md#L10` → the path and the line.
    private static func splitLine(_ href: String) -> (String, Int?) {
        if let hash = href.range(of: "#L", options: .backwards),
           let line = Int(href[hash.upperBound...].prefix(while: \.isNumber)) {
            return (String(href[..<hash.lowerBound]), line)
        }
        var path = Substring(href)
        var numbers: [Int] = []
        while let colon = path.lastIndex(of: ":"), let n = Int(path[path.index(after: colon)...]) {
            numbers.insert(n, at: 0)
            path = path[..<colon]
        }
        return (String(path), numbers.first)
    }

    /// The base URI with its path replaced, keeping scheme and machine.
    private static func rebuild(_ base: URL, pathSegments: [String]) -> String {
        let encoded = pathSegments.map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? $0
        }
        let scheme = base.scheme ?? "file"
        if scheme == FolderURI.brokerScheme, (base.host() ?? "").isEmpty,
           let machine = FolderURI.machine(base.absoluteString) {
            // `ahp-file:///<machine>/<rel>`: the machine is the first segment.
            return "\(scheme):///\(machine)" + (encoded.isEmpty ? "" : "/" + encoded.joined(separator: "/"))
        }
        let host = base.host(percentEncoded: true) ?? ""
        return "\(scheme)://\(host)/" + encoded.joined(separator: "/")
    }

    private static func onSameMachine(_ base: URL, absolutePath: String) -> String {
        let scheme = base.scheme ?? "file"
        let path = absolutePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? absolutePath
        if scheme == FolderURI.brokerScheme, let machine = FolderURI.machine(base.absoluteString) {
            return "\(scheme)://\(machine)\(path)"
        }
        return "\(scheme)://\(base.host(percentEncoded: true) ?? "")\(path)"
    }
}
