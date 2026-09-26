import AgentHostProtocol
import Testing
@testable import AHPApp

/// The gateway lists its machines in root `_meta`; the app reads them to name
/// where a session runs and which agents a folder's machine offers.
struct MachineTests {
    let meta: [String: AnyCodable] = [
        Machine.metaKey: AnyCodable([
            ["id": "my-mac-mini", "label": "Mac mini", "folder": "ahp-file:///my-mac-mini/",
             "connected": true, "agents": ["claude"]],
            ["id": "studio", "label": "Studio", "folder": "ahp-file:///studio/",
             "connected": true, "agents": ["claude", "opencode", "goose"]],
            ["id": "laptop", "connected": false],
        ] as [Any]),
    ]

    @Test func machinesAreReadFromTheGatewaysMeta() {
        let machines = Machine.list(from: meta)
        #expect(machines.map(\.id) == ["my-mac-mini", "studio", "laptop"])
        #expect(machines[1].label == "Studio")
        #expect(machines[1].agents == ["claude", "opencode", "goose"])
        // No label: the id. Offline: no agents.
        #expect(machines[2].label == "laptop")
        #expect(machines[2].connected == false)
        #expect(machines[2].agents.isEmpty)
    }

    @Test func aGatewayFromBeforeTheRenameIsStillRead() {
        let legacy = [Machine.legacyMetaKey: meta[Machine.metaKey]!]
        #expect(Machine.list(from: legacy).map(\.id) == ["my-mac-mini", "studio", "laptop"])
    }

    @Test func aHostWithNoListHasNoMachines() {
        #expect(Machine.list(from: nil).isEmpty)
        #expect(Machine.list(from: ["other": AnyCodable("x")]).isEmpty)
    }

    @Test func aFolderNamesItsMachine() {
        let machines = Machine.list(from: meta)
        #expect(Machine.of("ahp-file:///studio/llm/repo", in: machines)?.label == "Studio")
        #expect(Machine.of("file://my-mac-mini/Users/me", in: machines)?.label == "Mac mini")
        #expect(Machine.of("file:///Users/me", in: machines) == nil)
        #expect(Machine.of(nil, in: machines) == nil)
    }
}
