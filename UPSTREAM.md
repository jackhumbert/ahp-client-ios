# Upstream pin

This app is a fork of `AHPApp`, the sample iOS client that Microsoft ships
inside [`microsoft/agent-host-protocol`](https://github.com/microsoft/agent-host-protocol)
at `clients/swift/AHPApp/` (MIT — see [`LICENSE`](LICENSE), which is upstream's,
unmodified).

Two things are pinned, and they must move together:

| What | Pinned to | Where |
|---|---|---|
| The app source this fork started from | tag `v0.9.0` = commit `60706330f2f351b09f150d9a9c3c0eaedfc8e8b9` (= `spec/v0.9.0`) | this repository's history |
| The Swift package the app links (`AgentHostProtocol`, `AgentHostProtocolClient`) | `exactVersion 0.9.0` | `AHPApp.xcodeproj/project.pbxproj`, `Package.resolved` |

`v0.9.0` is the same spec revision the Python family pins
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
  it is now the remote repository at `exactVersion 0.9.0`. SwiftPM resolves
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
