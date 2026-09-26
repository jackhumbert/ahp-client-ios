import SwiftUI

extension ConnectionStage {
    /// What to tell the user about this stage, or `nil` when nothing is in
    /// flight. `now` drives the seconds shown while waiting or retrying, so a
    /// slow server reads as slow rather than stuck.
    func label(serverName: String?, now: Date) -> String? {
        switch self {
        case .idle:
            return nil
        case .checking:
            return "Checking connection…"
        case .opening(let attempt, let total):
            return attempt > 1 ? "Connecting (attempt \(attempt) of \(total))…" : "Connecting…"
        case .waitingForServer(let since):
            let who = serverName ?? "the server"
            let seconds = Int(now.timeIntervalSince(since))
            return seconds < 2 ? "Waiting for \(who)…" : "Waiting for \(who)… \(seconds)s"
        case .loadingSessions:
            return "Loading sessions…"
        case .retrying(_, _, let at):
            let seconds = max(1, Int(at.timeIntervalSince(now).rounded(.up)))
            return "Couldn't connect. Retrying in \(seconds)s…"
        }
    }
}

/// The current connection stage as text, ticking once a second so the
/// waiting and retrying counts stay current.
struct ConnectionStageText: View {
    let stage: ConnectionStage
    let serverName: String?
    /// Shown when `stage` is idle.
    var fallback: String = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(stage.label(serverName: serverName, now: context.date) ?? fallback)
                .monospacedDigit()
        }
    }
}
