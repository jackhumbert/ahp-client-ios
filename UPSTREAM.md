# Upstream pin

This app is a fork of `AHPApp`, the sample iOS client that Microsoft ships
inside [`microsoft/agent-host-protocol`](https://github.com/microsoft/agent-host-protocol)
at `clients/swift/AHPApp/` (MIT — see [`LICENSE`](LICENSE), which is upstream's,
unmodified).

Two things are pinned, and they must move together:

| What | Pinned to | Where |
|---|---|---|
| Upstream's app source, ported up to | `main` @ commit `1ef0642965efaa7ef98caff287bca923fbc80ec6` (spec `1.1.0`, not yet tagged) | this repository's history |
| The Swift package the app links (`AgentHostProtocol`, `AgentHostProtocolClient`) | `revision 1ef0642965efaa7ef98caff287bca923fbc80ec6` | `AHPApp.xcodeproj/project.pbxproj`, `Package.resolved` |

`1ef06429` is the same upstream commit the Python family pins
(`ahp-py/packages/ahp-protocol/UPSTREAM.md`), so this app, the Python host and the
Python client all speak the same protocol version. Both pin a commit on `main`
rather than a tag because the hosts already keep 1.1.0 state (below); move both
to `v1.1.0` once upstream tags it.

## How the fork was cut

History was kept, not squashed: the first ten commits here are upstream's own,
rewritten by `git filter-branch --subdirectory-filter clients/swift/AHPApp` on a
throwaway clone at `v0.9.0`. History before upstream's `AHPClient` → `AHPApp`
rename (`eeedffeb`, #131) is not reachable through that filter and was not
brought over.

Changes made on top of upstream at fork time:

- The package reference was upstream's local `../../..` (the monorepo root);
  it is now the remote repository at an exact version. SwiftPM resolves
  bare `vX.Y.Z` tags, which upstream reserves for Swift releases.
- `IPHONEOS_DEPLOYMENT_TARGET` lowered from `26.2` to `26.0`. The app already
  gates every iOS 26 API behind `#available(iOS 26.0, *)`.

## Moving the pin

Exact, not `upToNextMinor`: the spec lands breaking changes in MINOR bumps, and
the app's views read generated types directly. That means `exactVersion` on a
release tag, or `revision` on a commit when the Python family has moved ahead
of a tag, as it has now.

1. Bump the package requirement in `project.pbxproj` and run
   `xcodebuild -resolvePackageDependencies -project AHPApp.xcodeproj -scheme AHPApp`.
2. Diff upstream's `clients/swift/AHPApp/` between the old and new tag and port
   what applies — upstream adapts the app to each type change in the same PR
   that makes it, so that diff is the migration guide.
3. Update both rows of the table above.

## Pin history

- **`v0.9.0` → `v1.0.0`.** Every spec change is additive. Upstream's app diff
  is one line, merging `chats` from `root/sessionSummaryChanged` into the
  cached summary; `defaultChat` is merged alongside it here. The one SDK break
  is `ToolResultFileEditContent.diff`, now a typed `FileEditDiffStats` instead
  of `AnyCodable`. The 1.0.0 additions — chat background work, canvases,
  `moveChat`, per-chat read and archive state — were decoded but not shown;
  chats and background work are now shown (see README).
- **`v1.0.0` → `main` @ `1ef06429` (spec 1.1.0, untagged).** Followed the
  Python family, which absorbed 1.1.0 ahead of its tag. Its hosts keep a chat's
  state in 1.1.0's shape whatever version a client negotiates, and 1.1.0
  changed that shape: steering and queued messages share `queuedMessages`,
  each tagged with a `kind`, and `steeringMessage` is a deprecated mirror of a
  steering entry. A 1.0.0 app showed a steering message twice after
  subscribing, and kept a stale "Later" copy once the agent took it. The chat
  now shows `ChatState.pendingMessages` (`Store/PendingMessages.swift`), which
  reads the shared list by kind and adds the mirror only for a 1.0.0 host that
  keeps steering nowhere else. Upstream's app diff is a doc comment. Nothing
  else broke the build; chat config, TCP connections, `ModelInfo.vendor` and
  channel flow control are decoded but not used.
