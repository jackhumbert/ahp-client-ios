# Deferred upstream reports

Measured defects that belong to `microsoft/agent-host-protocol`, held until they
can be filed. Two rules, as in the sibling repositories: only measured things go
in, and if one turns out to be ours, delete it rather than leave a wrong
accusation lying around.

## 1. `AHPApp` does not compile against its own package at any Swift release

**Measured** at `v0.9.0` (`60706330`), Xcode 27.0, by building
`clients/swift/AHPApp` with the package it ships beside.

The multi-chat change (`b3319ca4`, #213, 2026-06-15) moved turns, tool-call
confirmation and input requests from the session channel to chat channels and
renamed the types (`SessionTurnStartedAction` → `ChatTurnStartedAction`,
`SessionInputAnswer` → `ChatInputAnswer`, …). The package was regenerated; the
app's store and views were not. Later commits touched the app
(`271edac3`, `80454fd0`, `b4016c0e`) without restoring the build, which is
consistent with no CI job building it.

Every Swift tag (`v0.5.2` … `v0.9.0`) postdates #213, so there is no release at
which the app and package agree.

Symptoms at `v0.9.0`, first compiler pass: `cannot find type
'SessionInputAnswer'`, `SessionSummary has no member 'workingDirectory'`,
`switch must be exhaustive` over the open unions' new `.unknown` arm, and
`cannot convert 'String' to 'Int'` on `modifiedAt` (now ISO 8601). Fixing those
exposes the rest: `session.turns`, `sessionTurnCancelled`,
`sessionToolCallConfirmed` and `CreateSessionParams.model` no longer exist.

The port in this repository (commit "feat!: port to multi-chat") is the
evidence of what the app needs; it could be offered upstream as the fix.

**Suggested fix upstream:** add `xcodebuild build` of `AHPApp` to the Swift CI
workflow.

## 2. `TerminalLifecycleState` is a closed union

**Measured** in `Generated/State.generated.swift` at `v0.9.0`: its
`init(from:)` throws `DecodingError.dataCorruptedError` on any `status` other
than `running` / `exited`. Every other open union in the same file decodes an
unknown discriminant to `.unknown(AnyCodable)` and re-encodes it verbatim
(`48112b2c`, "swift: preserve missing open-union discriminants").

Consequence: a host that adds a terminal lifecycle status makes every terminal
snapshot from it undecodable in the Swift client, not just unrendered.

Not yet reproduced against a live host — this is a reading of the generated
decoder. Confirm with a unit decode of `{"status": "suspended"}` before filing.

## 3. `SnapshotState` reports the wrong type's decoding error

**Measured** at `v0.9.0`, 2026-09-26, through the broker. `SnapshotState`'s
`init(from:)` (`Generated/State.generated.swift`) tries each state type with
`try?` and falls back to `try RootState(from:)`, so when nothing matches, the
error that surfaces is always RootState's. A chat snapshot with one turn
missing the required `Message.origin` (a host bug, fixed in
`agent-host-server-py` `c680bbc`) showed up in the app as
``keyNotFound: 'agents' … Path: snapshot.state``. Decoding the same JSON as
`ChatState` directly gave the real error: `keyNotFound: 'origin'`, path
`turns[0].message`.

Consequence: any out-of-spec field in any non-root snapshot is reported as a
missing `agents`, which points at the wrong channel entirely.

**Suggested fix upstream:** pick the arm from `Snapshot.resource` (or keep the
closest arm's error) instead of reporting the last fallback.
