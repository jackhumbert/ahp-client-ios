# Agent guide

For AI agents and humans maintaining this repository. Assume the reader starts
with zero context.

**Read first:** [`UPSTREAM.md`](UPSTREAM.md) — what this is a fork of, what is
pinned, and how to move the pin.

## What this project is

A native iOS (iPhone and iPad) **client** for the Agent Host Protocol, in Swift
and SwiftUI. AHP is an external specification owned by Microsoft; we implement
it, we do not design it.

It is a fork of upstream's sample app `AHPApp`, not a from-scratch client. The
protocol layer — generated wire types, the reducers, the WebSocket transport,
`MultiHostClient` — is upstream's Swift package `AgentHostProtocol`, consumed
unmodified from GitHub. This repository owns only the app on top of it.

Siblings in `~/Github`, all speaking the same spec revision:

| Repository | Role |
|---|---|
| `agent-host-protocol-py` | Python wire types, reducers, conformance corpora |
| `agent-host-server-py` | Python host — the one this app is tested against |
| `agent-host-client-py` | Python client |
| `agent-host-broker-py` | Python broker |

Current state: **working, pre-alpha.** Ported to spec 0.9.0; a full turn
completes in the iOS 26.5 simulator against `python -m agent_host_server`. Tool
approvals, input requests, terminals, reconnection and the broker are ported
but not yet exercised against a host.

The bundle ID is `com.jhumbert.agent-host-client` (upstream's
`com.rebornix.AHPApp` belongs to another developer account).

**Deferred upstream reports** live in
[`docs/deferred-upstream.md`](docs/deferred-upstream.md). Add to it when you find
one, while the evidence is in front of you.

## Sessions and chats

Since multi-chat, a session holds metadata and a list of chats; the
conversation — turns, the active turn, queued messages, input requests — lives
on a **chat** channel. `AppStore` subscribes each subscribed session's default
chat alongside it (`syncChatSubscription(forSession:)`), keeps chat state in
`chats`, and sends every conversation action to the chat URI. Views read the
conversation from `currentChat` and pending questions from
`currentInputRequests`, never from the session.

Incoming actions are routed by which table their channel is registered in —
never by URI scheme or prefix, because hosts choose their own URI shapes.

## Toolchain

- **Xcode 27** (macOS 27). The project is `objectVersion = 77` and uses
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with approachable concurrency;
  older Xcodes cannot open or correctly compile it.
- **Metal Toolchain** — `xcodebuild -downloadComponent MetalToolchain`. SwiftTerm
  compiles Metal shaders and the build fails without it.
- **Deployment target iOS 26.0.** Anything newer must sit behind
  `#available`, so the app keeps installing on iOS 26 devices.

## Commands

```bash
xcodebuild -resolvePackageDependencies -project AHPApp.xcodeproj -scheme AHPApp
xcodebuild build -project AHPApp.xcodeproj -scheme AHPApp \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project AHPApp.xcodeproj -scheme AHPApp \
  -destination 'platform=iOS Simulator,name=<device>'
```

The host to test against, from `../agent-host-server-py`:

```bash
python -m agent_host_server --delay 0.05
```

It listens on `127.0.0.1:4321`, which the simulator reaches directly. A
physical device needs `--allow-remote` (read that repository's security section
first) and `--token`.

Code signing for a device reads `AHP_DEVELOPMENT_TEAM` from
`AHPApp/Config/Signing.local.xcconfig` (gitignored; copy the `.example`).

## Seeing what a host actually sent

Before blaming the app for something missing on screen, look at the wire:

- **Live conversations** (through `broker.example.com`): the user-level Claude
  Code skill `ahp-broker` (`~/.claude/skills/ahp-broker/`) lists sessions and
  prints each turn's tool calls exactly as the host sent them. It is read-only.
  Its token lives in `.local/broker-test.token` here — gitignored, mode 0600,
  label `claude-code-test` on the broker; never print or commit it.
- **A reproducible host**: `scripts/fake_bash_host.py` serves one agent on
  `127.0.0.1:4397` whose every turn replays a Claude-Code-shaped `Bash` call
  (generic invocation message, command in `toolInput`). Run it with
  `../agent-host-server-py/.venv/bin/python`.

## Layout

| Path | Contents |
|---|---|
| `AHPApp/Store/` | `AppStore` (the `@Observable` state container), `AHPConnection` (wraps `MultiHostClient`), server persistence |
| `AHPApp/Views/` | SwiftUI — sidebar, chat, response/request parts, input requests, terminal, tunnels, settings |
| `AHPAppTests/`, `AHPAppUITests/` | upstream's tests for the app |

Upstream's description of the app's architecture lives in
`clients/swift/AGENTS.md` in their repository, under `## AHPApp`. Parts of it are
stale — it describes `AHPConnection` as wrapping `URLSessionWebSocketTask`,
while the code uses `MultiHostClient` over an `NWConnection` transport. The code
wins.

## Rules

- **Do not patch the protocol package.** A defect in `AgentHostProtocol` is
  upstream's to fix: record it (evidence, not opinion) for reporting upstream,
  and work around it in the app with a comment pointing at the record. Forking
  the package would mean owning roughly 19,000 lines of generated types, reducers and client.
- **Keep the fork mergeable.** Upstream keeps adapting this app to every spec
  change. Prefer additions over rewrites of upstream files, and keep unrelated
  reformatting out of diffs, so the next pin bump is a port rather than a
  rewrite.
- **Commits** are conventional (`feat:`, `fix:`, `docs:` …), as in the sibling
  repositories.
- **If a feature is not documented, it does not exist.** A change is not
  finished until the README's claims still hold.
