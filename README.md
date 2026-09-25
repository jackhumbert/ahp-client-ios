# agent-host-client-ios

A native iOS client for the [Agent Host Protocol][ahp] (AHP) — Microsoft's
protocol for synchronized multi-client state over AI agent sessions. SwiftUI,
iPhone and iPad, iOS 26 and later.

> ### ⚠️ Status: working, pre-alpha.
>
> A fork of `AHPApp`, the sample app in
> [`microsoft/agent-host-protocol`][upstream], pinned to `v0.9.0`
> ([`UPSTREAM.md`](UPSTREAM.md)). Upstream's app had not compiled against its
> own package since the protocol moved conversations onto chat channels
> ([`docs/deferred-upstream.md`](docs/deferred-upstream.md)); this fork is ported
> to that model. A full turn completes in the iOS 26.5 simulator against the
> sibling Python host. Not yet exercised: tool approvals, questions from the
> agent, terminals, reconnection, the broker.

## What it does

As inherited from upstream, plus the session settings:

- Connect to one or more AHP hosts over `ws://` or `wss://`, with reconnection
  that replays missed actions when the app returns from the background
- Several agents on one server: the session list's card shows each agent by
  name with its own counts, and tapping one narrows the list to it
- Several machines behind agent-host-broker (which lists them in root `_meta`):
  the card shows a row per machine with the agents it runs, sessions say where
  they run ("Claude · Studio"), the folder browser names machines, and a new
  chat picks its folder first, then offers only that machine's agents
- Browse sessions, and start new ones with an agent, model and working
  directory — picked from pinned or recent folders, by browsing the host's folders
  (push navigation, a filter, swipe to choose or pin; through a broker too,
  starting from its list of machines), or typed
- A new session's **settings**, as the host describes them
  (`resolveSessionConfig`): each choice the host offers — for the Claude Code
  host, **Approvals** (Ask / Accept edits / Auto / Plan) and **Continue from** —
  appears in the New Chat sheet and is sent with `createSession`. The chat
  screen shows the approval mode it was created with; a host that allows
  changing it mid-session gets a picker instead
- Choose what shows under each reply (Settings → Reply Details): time
  received, duration, model, tool calls, input/output/cached tokens, in any
  order — time received by default
- Send while the agent is working: **Next** (the default tap) joins the turn
  in flight, **Later** runs after it, **Now** stops it and sends yours
  (long-press Send). Waiting messages can be cancelled; a message that joined
  a turn is shown where it joined
- Tool calls as cards, compact one-liners, or collapsed runs ("5 tool calls ✓")
  that expand (Settings → Tool Calls); a call waiting on you is always a card
- Browse the session's files and open them — markdown rendered, code with line
  numbers, images — from the chat's folder button; links in replies to files
  (`[a](src/a.swift:42)`, relative or absolute) open the file at that line
- Stream chat responses — markdown with headings, lists, code blocks, tables
  and quotes, reasoning, tool calls with their inputs and
  outputs
- Tool-call cards show what actually ran — the shell command, or the file,
  pattern or URL — not only the host's one-line message
- Answer the agent's questions and tool confirmations
- An interactive terminal (SwiftTerm)
- Microsoft dev tunnels as a way to reach a host (GitHub sign-in)

## Build

Requires Xcode 27 and its Metal Toolchain
(`xcodebuild -downloadComponent MetalToolchain`).

```bash
open AHPApp.xcodeproj
```

Try it against the sibling Python host:

```bash
python -m agent_host_server --delay 0.05
```

then add the server `127.0.0.1:4321` (scheme `ws`) in the app. Behind the broker,
use scheme `wss`, host `broker.example.com`, and a personal broker token in the
Token field — the app sends it as `?tkn=`, which the broker's Caddy route accepts.

## Install on a phone with SideStore

SideStore re-signs whatever it installs with your own Apple ID, so it takes an
unsigned build:

```bash
xcodebuild archive -project AHPApp.xcodeproj -scheme AHPApp -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/AHPApp.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
mkdir -p build/ipa/Payload
cp -R build/AHPApp.xcarchive/Products/Applications/AHPApp.app build/ipa/Payload/
(cd build/ipa && zip -qry AgentHostClient.ipa Payload)
```

Put `build/ipa/AgentHostClient.ipa` somewhere the phone can reach (iCloud Drive
works) and open it with SideStore.

To install from Xcode instead, copy `AHPApp/Config/Signing.local.xcconfig.example`
to `Signing.local.xcconfig` and set your team ID. A free Personal Team can only
create a profile once a device has been connected to this Mac.

## License

MIT, upstream's — see [`LICENSE`](LICENSE).

[ahp]: https://microsoft.github.io/agent-host-protocol/
[upstream]: https://github.com/microsoft/agent-host-protocol
