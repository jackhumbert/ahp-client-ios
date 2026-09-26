import Foundation

#if DEBUG && targetEnvironment(simulator)
/// Simulator-only: a server handed in at launch, so automated testing can
/// reach a token-protected host (the gateway) without anyone typing the token
/// into a text field.
///
///     SIMCTL_CHILD_AHP_DEBUG_SERVER=wss://gateway.example.com \
///     SIMCTL_CHILD_AHP_DEBUG_TOKEN="$(cat .local/gateway-test.token)" \
///       xcrun simctl launch <device> com.jhumbert.agent-host-client
///
/// `simctl` strips the `SIMCTL_CHILD_` prefix. Compiled out of every device
/// and release build, so no IPA contains it.
extension AppStore {
    func applyDebugLaunchServer(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let raw = environment["AHP_DEBUG_SERVER"],
              let url = URL(string: raw),
              let scheme = url.scheme, ["ws", "wss"].contains(scheme),
              let host = url.host() else { return }
        let hostPort = url.port.map { "\(host):\($0)" } ?? host
        let name = environment["AHP_DEBUG_SERVER_NAME"] ?? "\(host) (debug)"
        let token = environment["AHP_DEBUG_TOKEN"] ?? ""

        if var existing = servers.first(where: { $0.name == name }) {
            // Refresh in place, so a re-minted token takes over on relaunch.
            existing.scheme = scheme
            existing.host = hostPort
            existing.token = token
            updateServer(existing)
            selectedServerId = existing.id
        } else {
            let server = ServerConfiguration(name: name, scheme: scheme, host: hostPort, token: token)
            addServer(server)
            selectedServerId = server.id
        }
    }
}
#endif
