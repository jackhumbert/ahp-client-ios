import Testing
@testable import AHPApp

/// Links in replies point at files relative to the session's folder; they
/// must resolve to a URI the same host (and, through a broker, the same
/// machine) can read.
struct FileLinkTests {
    let local = "file:///Users/me/repo"
    let broker = "ahp-file:///my-mac-mini/agent-host-client-ios"
    let deployed = "file://my-mac-mini/Users/me/repo"

    @Test func relativeLinksResolveAgainstTheWorkingFolder() {
        #expect(FileLink.resolve("README.md", base: local) == FileLink(uri: "file:///Users/me/repo/README.md", line: nil))
        #expect(FileLink.resolve("./docs/a.md", base: local)?.uri == "file:///Users/me/repo/docs/a.md")
        #expect(FileLink.resolve("../other/b.md", base: local)?.uri == "file:///Users/me/other/b.md")
    }

    @Test func linesComeFromColonsAndAnchors() {
        #expect(FileLink.resolve("src/foo.swift:42", base: local) == FileLink(uri: "file:///Users/me/repo/src/foo.swift", line: 42))
        #expect(FileLink.resolve("src/foo.swift:42:7", base: local)?.line == 42)
        #expect(FileLink.resolve("README.md:10", base: local) == FileLink(uri: "file:///Users/me/repo/README.md", line: 10))
        #expect(FileLink.resolve("docs/a.md#L3", base: local)?.line == 3)
    }

    @Test func throughTheBrokerTheMachineIsKept() {
        #expect(FileLink.resolve("AHPApp/Views/ChatView.swift", base: broker)?.uri
            == "ahp-file:///my-mac-mini/agent-host-client-ios/AHPApp/Views/ChatView.swift")
        #expect(FileLink.resolve("README.md", base: deployed)?.uri == "file://my-mac-mini/Users/me/repo/README.md")
        #expect(FileLink.resolve("/etc/hosts", base: broker)?.uri == "ahp-file://my-mac-mini/etc/hosts")
    }

    @Test func webLinksAreNotFiles() {
        #expect(FileLink.resolve("https://example.com/a.md", base: local) == nil)
        #expect(FileLink.resolve("mailto:a@b.c", base: local) == nil)
    }

    @Test func spacesAreEncoded() {
        #expect(FileLink.resolve("My%20Notes/a.md", base: local)?.uri == "file:///Users/me/repo/My%20Notes/a.md")
    }
}
