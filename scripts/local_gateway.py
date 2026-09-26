"""Test-only: a gateway on 127.0.0.1:4396 in front of two local hosts.

Reproduces what a deployed gateway looks like to the app — several agents on
one server, machine-qualified folder URIs — without a token. It runs the
ahp-gateway in the sibling `../ahp-py` checkout, which serves
`ahp-file:///<machine>/…` and lists machines at `ahp-file:///`. Admits every
loopback connection, so never bind it anywhere else.

    # node "mac-a": the echo host, serving a folder tree to browse
    ../ahp-py/.venv/bin/python -m ahp_host --port 4399 --serve-directory /some/dir
    # node "mac-b": the fake Bash agent
    ../ahp-py/.venv/bin/python scripts/fake_bash_host.py
    # the gateway
    ../ahp-py/.venv/bin/python scripts/local_gateway.py

Then add server 127.0.0.1:4396 (ws, no token) in the app.
"""

import asyncio

from ahp_gateway.core import Gateway, GatewayInfo
from ahp_gateway.registry import NodeRecord, Principal, StaticInventory
from ahp_gateway.ws import NodeCredentials, WebSocketNodeConnector, serve_gateway

OWNER = frozenset({"owner"})
NODES = [
    NodeRecord("mac-a", "ws://127.0.0.1:4399/", OWNER),
    NodeRecord("mac-b", "ws://127.0.0.1:4397/", OWNER),
]


async def main() -> None:
    gateway = Gateway(
        StaticInventory(NODES),
        WebSocketNodeConnector(lambda record, principal: NodeCredentials()),
        lambda info: Principal("tester", OWNER),
        info=GatewayInfo(title="local gateway"),
    )
    async with serve_gateway(gateway, port=4396):
        print("local gateway on 127.0.0.1:4396:", ", ".join(n.node_id for n in NODES), flush=True)
        await asyncio.Event().wait()


asyncio.run(main())
