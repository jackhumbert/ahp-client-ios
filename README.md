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

As inherited from upstream:

- Connect to one or more AHP hosts over `ws://` or `wss://`, with reconnection
  that replays missed actions when the app returns from the background
- Browse sessions, start new ones with an agent, model and working directory
- Stream chat responses — markdown, reasoning, tool calls with their inputs and
  outputs
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
