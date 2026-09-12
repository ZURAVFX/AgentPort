"""Bounded MCP handshake and optional read-only application check."""
import asyncio
import json
import os
import sys
from contextlib import AsyncExitStack

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.client.streamable_http import streamablehttp_client


async def check(config):
    async with AsyncExitStack() as stack:
        if config.get("transport") == "streamable-http":
            streams = await stack.enter_async_context(streamablehttp_client(config["url"], headers=config.get("headers")))
        else:
            streams = await stack.enter_async_context(stdio_client(StdioServerParameters(
                command=config["command"], args=config.get("args", []),
                env={**os.environ, **config.get("env", {})}, cwd=config.get("cwd"))))
        session = await stack.enter_async_context(ClientSession(streams[0], streams[1]))
        await session.initialize()
        listing = await session.list_tools()
        names = [tool.name for tool in listing.tools]
        result = {"tools": names, "count": len(names), "connected": True}
        probe = config.get("probe")
        if probe:
            reply = await session.call_tool(probe, config.get("probeArgs", {}))
            result["applicationOk"] = not reply.isError
            result["reply"] = [item.text for item in reply.content if item.type == "text"]
        return result


if __name__ == "__main__":
    try:
        config = json.loads(sys.stdin.read().lstrip('\ufeff'))
        print(json.dumps(asyncio.run(asyncio.wait_for(check(config), timeout=60))))
    except BaseException as error:
        print(json.dumps({"connected": False, "error": str(error)}))
        sys.exit(1)
