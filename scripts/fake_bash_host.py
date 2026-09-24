"""Test-only host: every message replays one Bash call shaped like agent-host-server-claude's."""
import asyncio, json
from agent_host_server import Host, LoopbackSingleUserPolicy
from agent_host_server.provider.base import AgentInfo, AgentSessionContext, ModelInfo, TurnSink, UserMessage
from agent_host_server.ws import serve_websocket

INPUT = {"command": "git ls-files | grep -v '^vehicles/.*/attachments/' | head -200 && echo --- && git ls-files | wc -l",
         "description": "Survey repo files, history, and conventions"}

class S:
    def __init__(self, ctx): self.n = 0
    async def send_user_message(self, message: UserMessage, sink: TurnSink) -> None:
        self.n += 1
        cid = f"call-{self.n}"
        await sink.tool_call_started(cid, "Bash", json.dumps(INPUT), display_name="Run command")
        await sink.tool_call_completed(cid, [{"type": "text", "text": "AGENTS.md\nREADME.md\n---\n42"}], success=True, past_tense_message="Done")
        await sink.text_delta("Replayed one Bash call.")
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
