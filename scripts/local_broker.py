"""Test-only: a broker on 127.0.0.1:4396 in front of two local hosts.

Reproduces what broker.example.com looks like to the app — several agents on
one server, machine-qualified folder URIs — without a token. It runs whatever
agent-host-broker the sibling checkout has: at the time of writing that serves
`ahp-file:///<machine>/…` and lists machines at `ahp-file:///`, where the
deployed broker still sends `file://<machine>/…`. Admits every loopback connection, so never bind it anywhere else.

    # node "mac-a": the echo host, serving a folder tree to browse
    ../agent-host-server-py/.venv/bin/python -m agent_host_server --port 4399 --serve-directory /some/dir
    # node "mac-b": the fake Bash agent
    ../agent-host-server-py/.venv/bin/python scripts/fake_bash_host.py
    # the broker
    ../agent-host-broker-py/.venv/bin/python scripts/local_broker.py

Then add server 127.0.0.1:4396 (ws, no token) in the app.
"""

import asyncio

from agent_host_broker.core import Broker, BrokerInfo
from agent_host_broker.registry import NodeRecord, Principal, StaticInventory
from agent_host_broker.ws import NodeCredentials, WebSocketNodeConnector, serve_broker

OWNER = frozenset({"owner"})
NODES = [
    NodeRecord("mac-a", "ws://127.0.0.1:4399/", OWNER),
    NodeRecord("mac-b", "ws://127.0.0.1:4397/", OWNER),
]


async def main() -> None:
    broker = Broker(
        StaticInventory(NODES),
        WebSocketNodeConnector(lambda record, principal: NodeCredentials()),
        lambda info: Principal("tester", OWNER),
        info=BrokerInfo(title="local broker"),
    )
    async with serve_broker(broker, port=4396):
        print("local broker on 127.0.0.1:4396:", ", ".join(n.node_id for n in NODES), flush=True)
        await asyncio.Event().wait()


asyncio.run(main())
