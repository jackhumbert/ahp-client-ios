import AgentHostProtocol
import Foundation

/// A machine behind a gateway, from `RootState._meta["ahp-gateway/nodes"]`.
///
/// AHP has no notion of a machine: to the app a gateway is one host, an agent
/// offered on several machines is one agent, and a session's folder
/// (`ahp-file:///<machine>/…`) says where it runs. The gateway lists its
/// machines in root `_meta` so the app can say "Claude on Studio", group by
/// machine, and offer only the agents a folder's machine runs. A host that
/// sends no list is one machine, and none of this shows.
struct Machine: Identifiable, Equatable, Hashable {
    /// The node id: the first path segment of its folders.
    let id: String
    let label: String
    /// Its folder tree's root, `ahp-file:///<id>/`.
    let folder: String
    let connected: Bool
    /// Provider ids of the agents it runs; empty while it is not connected.
    let agents: [String]

    static let metaKey = "ahp-gateway/nodes"
    /// What gateways sent before the rename from agent-host-broker. Remove
    /// once no deployed gateway predates it.
    static let legacyMetaKey = "agent-host-broker/nodes"

    /// The gateway's list, or empty when the host sent none.
    static func list(from meta: [String: AnyCodable]?) -> [Machine] {
        guard let entries = (meta?[metaKey] ?? meta?[legacyMetaKey])?.value as? [Any] else { return [] }
        return entries.compactMap { entry in
            guard let fields = entry as? [String: Any], let id = fields["id"] as? String, !id.isEmpty else {
                return nil
            }
            return Machine(
                id: id,
                label: (fields["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id,
                folder: fields["folder"] as? String ?? "\(FolderURI.gatewayRoot)\(id)/",
                connected: fields["connected"] as? Bool ?? true,
                agents: (fields["agents"] as? [Any])?.compactMap { $0 as? String } ?? []
            )
        }
    }

    /// The machine in `machines` a folder or file URI is on.
    static func of(_ uri: String?, in machines: [Machine]) -> Machine? {
        guard let uri, let id = FolderURI.machine(uri) else { return nil }
        return machines.first { $0.id == id }
    }
}

extension AppStore {
    /// The machines behind the connected gateway; empty for a single host.
    var machines: [Machine] {
        Machine.list(from: rootState.meta)
    }

    /// Whether there is more than one machine to tell apart.
    var hasSeveralMachines: Bool { machines.count > 1 }

    /// The machine a session runs on, from its folder.
    func machine(of summary: SessionSummary) -> Machine? {
        Machine.of(summary.workingDirectories?.first, in: machines)
    }

    /// The machine a folder is on.
    func machine(forFolder uri: String?) -> Machine? {
        Machine.of(uri, in: machines)
    }

    /// The agents that can start a session in `folder`: those its machine
    /// runs, or every agent when the host lists no machines or the folder
    /// names none.
    func agents(forFolder folder: String?) -> [AgentInfo] {
        guard let machine = machine(forFolder: folder), !machine.agents.isEmpty else { return agents }
        return agents.filter { machine.agents.contains($0.provider) }
    }

    /// "Claude" alone, or "Claude · Studio" when there are machines to tell apart.
    func agentLabel(for summary: SessionSummary) -> String {
        let name = agentName(for: summary.provider)
        guard hasSeveralMachines, let machine = machine(of: summary) else { return name }
        return "\(name) · \(machine.label)"
    }
}
