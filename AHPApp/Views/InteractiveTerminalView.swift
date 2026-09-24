import AgentHostProtocol
import SwiftTerm
import SwiftUI
import UIKit

/// Full-screen interactive terminal backed by an AHP terminal process.
struct InteractiveTerminalView: View {
    let terminalURI: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var state: TerminalState? {
        store.terminals[terminalURI]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let state, !state.content.isEmpty || !state.hasExited {
                AHPTerminalSwiftUIView(terminalURI: terminalURI)
                    .ignoresSafeArea(.container, edges: .bottom)
            } else if state?.hasExited == true {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(state?.exitCode.map { "Terminal exited with code \($0)" } ?? "Terminal exited")
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Connecting…")
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle(state?.title ?? "Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await store.disposeTerminal(uri: terminalURI)
                    }
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await store.ensureTerminalSubscribed(uri: terminalURI)
        }
    }
}

extension TerminalState {
    /// Since 0.9.0 `terminal/exited` records the exit in `lifecycle`
    /// (`{status: "exited", exitCode?}`) instead of a top-level `exitCode`,
    /// and an exited terminal may carry no code at all.
    var hasExited: Bool {
        if case .exited = lifecycle { return true }
        return false
    }

    var exitCode: Int? {
        if case .exited(let exited) = lifecycle { return exited.exitCode }
        return nil
    }
}
