"""Test-only host: every message starts a subagent and a background shell.

Serves one agent on 127.0.0.1:4398. Each turn calls a `Task` tool whose result
links a worker chat (read-only, `tool` origin), lists that subagent and a
shell as the chat's background work, and ends while both keep running: the
worker writes its own turn for ~20 s, the shell prints to its terminal for
~30 s, and each leaves the background list when it finishes.

Run it with the sibling checkout's venv:

    ../ahp-py/.venv/bin/python scripts/fake_subagent_host.py
"""
import asyncio, json
from ahp_host import Host, LoopbackSingleUserPolicy
from ahp_host.provider.base import (
    AgentInfo, AgentSessionContext, BackgroundWork, ModelInfo, TurnSink, UserMessage,
)
from ahp_host.ws import serve_websocket


class S:
    def __init__(self, ctx: AgentSessionContext):
        self.publisher = ctx.publisher
        self.n = 0
        self.tasks: set[asyncio.Task] = set()

    def _spawn(self, coro) -> None:
        task = asyncio.create_task(coro)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)

    async def send_user_message(self, message: UserMessage, sink: TurnSink) -> None:
        self.n += 1
        n = self.n
        cid = f"task-{n}"
        await sink.tool_call_started(cid, "Task", json.dumps({"description": "Find the TODOs"}), display_name="Start subagent")
        worker = await self.publisher.open_tool_chat(f"Researcher {n}", tool_call_id=cid)
        await sink.tool_call_completed(cid, [{
            "type": "subagent", "resource": worker.resource, "title": f"Researcher {n}",
            "agentName": "researcher", "description": "Finds the TODOs in the repository",
        }], success=True, past_tense_message="Started subagent")
        await self.publisher.background_work_set(BackgroundWork(
            id=f"subagent-{n}", kind="subagent", label=f"Researcher {n}", chat=worker.resource))

        terminal = await self.publisher.open_terminal(f"Watch {n}")
        await self.publisher.background_work_set(BackgroundWork(
            id=f"shell-{n}", kind="shell", label="Watch tests", command="npm test -- --watch",
            terminal=terminal.resource))

        async def run_worker(wsink: TurnSink) -> None:
            for k in range(10):
                await wsink.text_delta(f"Looked at file {k + 1} of 10. ")
                await asyncio.sleep(2)
            await wsink.text_delta("\n\nFound 3 TODOs.")

        async def worker_then_done() -> None:
            await worker.run_turn("Find the TODOs in the repository", run_worker)
            await asyncio.sleep(21)
            await self.publisher.background_work_removed(f"subagent-{n}")

        async def shell() -> None:
            for k in range(15):
                await terminal.write(f"PASS test {k + 1}\r\n")
                await asyncio.sleep(2)
            await terminal.exited(0)
            await self.publisher.background_work_removed(f"shell-{n}")

        self._spawn(worker_then_done())
        self._spawn(shell())
        await sink.text_delta("A subagent is looking for TODOs, and the tests are running in the background.")

    async def cancel(self, reason=None): pass

    async def aclose(self):
        for task in list(self.tasks):
            task.cancel()


class P:
    @property
    def agent(self): return AgentInfo(provider="fakesub", display_name="Fake Subagents", description="test", models=(ModelInfo(id="m", name="m"),))
    async def create_session(self, ctx: AgentSessionContext): return S(ctx)


async def main():
    async with serve_websocket(Host(P(), LoopbackSingleUserPolicy()), port=4398):
        await asyncio.Event().wait()

asyncio.run(main())
