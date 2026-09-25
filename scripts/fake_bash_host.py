"""Test-only host: every message replays one Bash call shaped like agent-host-server-claude's."""
import asyncio, json
from agent_host_server import Host, LoopbackSingleUserPolicy
from agent_host_server.provider.base import AgentInfo, AgentSessionContext, ModelInfo, TurnSink, UserMessage
from agent_host_server.ws import serve_websocket

INPUT = {"command": "git ls-files | grep -v '^vehicles/.*/attachments/' | head -200 && echo --- && git ls-files | wc -l",
         "description": "Survey repo files, history, and conventions"}

#: Block markdown as Claude writes it, to check the app renders blocks, not hashes.
REPLY = """### Findings

The survey found **42** tracked files; see [the README](README.md) and
[`ChatView.swift:40`](AHPApp/Views/ChatView.swift:40).

- Docs are thin
  - `README.md` has no setup section
1. Add a setup section
2. Add CI

```sh
git ls-files | wc -l
```

| Area | State |
|---|---|
| Docs | thin |
| Tests | none |

> Worth doing before the next release.
"""

class S:
    def __init__(self, ctx): self.n = 0
    async def send_user_message(self, message: UserMessage, sink: TurnSink) -> None:
        self.n += 1
        await sink.reasoning_delta("The user wants a survey. I'll list the tracked files, read the README, then look for TODOs.")
        if "tools" in message.text:
            # A long run of calls with no text between them, spaced out, to
            # check the app keeps up across backgrounding mid-turn.
            steps = 25 if "long" in message.text else 8
            for k in range(steps):
                cid = f"call-{self.n}-t{k}"
                await sink.tool_call_started(cid, "Bash", json.dumps({"command": f"step {k + 1}"}), display_name="Run command")
                await asyncio.sleep(4)
                await sink.tool_call_completed(cid, [{"type": "text", "text": "ok"}], success=True, past_tense_message=f"Ran step {k + 1}")
            await sink.text_delta(f"All {steps} steps ran.")
            return
        if "slow" in message.text:
            # Stays busy, so the session list shows it working.
            await asyncio.sleep(25)
        # Three calls in a row, to show how runs of calls are displayed.
        for k, (tool, display, args) in enumerate([
            ("Bash", "Run command", INPUT),
            ("Read", "Read file", {"file_path": "/repo/README.md"}),
            ("Grep", "Search", {"pattern": "TODO", "path": "/repo"}),
        ]):
            cid = f"call-{self.n}-{k}"
            await sink.tool_call_started(cid, tool, json.dumps(args), display_name=display)
            if tool == "Bash" and self.n % 2 == 0:
                # Every other turn, the command itself as the message (opencode
                # and the Windows node do this): the card shows the description.
                await sink.tool_call_delta(cid, invocation_message=INPUT["command"][:60] + "…")
            await sink.tool_call_completed(cid, [{"type": "text", "text": "ok"}], success=True, past_tense_message="Done")
        await sink.text_delta(REPLY)
    async def cancel(self, reason=None): pass
    async def aclose(self): pass

class P:
    @property
    def agent(self): return AgentInfo(provider="fakebash", display_name="Fake Bash", description="test", models=(ModelInfo(id="m", name="m"),))
    async def create_session(self, ctx: AgentSessionContext): return S(ctx)

async def main():
    async with serve_websocket(Host(P(), LoopbackSingleUserPolicy()), port=4397):
        await asyncio.Event().wait()

asyncio.run(main())
