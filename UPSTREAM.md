# Upstream pin

This app is a fork of `AHPApp`, the sample iOS client that Microsoft ships
inside [`microsoft/agent-host-protocol`](https://github.com/microsoft/agent-host-protocol)
at `clients/swift/AHPApp/` (MIT — see [`LICENSE`](LICENSE), which is upstream's,
unmodified).

Two things are pinned, and they must move together:

| What | Pinned to | Where |
|---|---|---|
| Upstream's app source, ported up to | tag `v1.0.0` = commit `5f16d81bb7045b66d7bc768d244feab75002d943` (= `spec/v1.0.0`) | this repository's history |
| The Swift package the app links (`AgentHostProtocol`, `AgentHostProtocolClient`) | `exactVersion 1.0.0` | `AHPApp.xcodeproj/project.pbxproj`, `Package.resolved` |

`v1.0.0` is the same spec revision the Python family pins
(`ahp-py/packages/ahp-protocol/UPSTREAM.md`), so this app, the Python host and the
Python client all speak the same protocol version.

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
the app's views read generated types directly.

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
