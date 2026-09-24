# agent-host-client-ios

A native iOS client for the [Agent Host Protocol][ahp] (AHP) — Microsoft's
protocol for synchronized multi-client state over AI agent sessions. SwiftUI,
iPhone and iPad, iOS 26 and later.

> ### ⚠️ Status: forked, not yet run.
>
> This is a fork of `AHPApp`, the sample app in
> [`microsoft/agent-host-protocol`][upstream], pinned to `v0.9.0`
> ([`UPSTREAM.md`](UPSTREAM.md)). It resolves its packages against that pin;
> it has not yet completed a turn against a host.

## What it does

As inherited from upstream, unchanged so far:

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

To run on a device, copy `AHPApp/Config/Signing.local.xcconfig.example` to
`Signing.local.xcconfig` and set your team ID.

Try it against the sibling Python host:

```bash
python -m agent_host_server --delay 0.05
```

then add the server `ws://127.0.0.1:4321` in the app.

## License

MIT, upstream's — see [`LICENSE`](LICENSE).

[ahp]: https://microsoft.github.io/agent-host-protocol/
[upstream]: https://github.com/microsoft/agent-host-protocol
