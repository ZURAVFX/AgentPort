"""Present a compact, explicit tool set to Harness; forward calls unchanged."""
import asyncio
import json
import os
from pathlib import Path
from urllib.parse import quote
import httpx
from mcp.types import Tool, TextContent, CallToolResult
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.server import Server
from mcp.server.stdio import stdio_server


async def main():
    config = json.loads(os.environ.pop("AGENTPORT_MCP_UPSTREAM"))
    allowed = set(config.pop("allowedTools"))
    async with stdio_client(StdioServerParameters(
        command=config["command"], args=config.get("args", []),
        env={**os.environ, **config.get("env", {})}, cwd=config.get("cwd"),
    )) as streams:
        async with ClientSession(*streams) as session:
            await session.initialize()
            listing = await session.list_tools()
            tools = [tool for tool in listing.tools if tool.name in allowed]
            # Keep schemas intact; long general usage guides dominate small requests.
            tools = [tool.model_copy(update={"description": (tool.description or "")[:1200]}) for tool in tools]
            comfy_url = config.get('env', {}).get('COMFY_LOCAL_URL')
            if comfy_url:
                # comfy-cli's discovery honours the selected port, but its workflow
                # verbs can fall back to 8188. These small REST-backed equivalents
                # keep every workflow action on the address the user connected.
                direct_names = {'nodes', 'server_info', 'system_stats', 'validate_workflow', 'run_workflow', 'job', 'fetch_outputs', 'free_memory'}
                tools = [tool for tool in tools if tool.name not in direct_names]
                tools.extend([
                    Tool(name='nodes', description='Inspect live ComfyUI nodes. Use class_names for exact node schemas (for example EmptyImage, SaveImage, CheckpointLoaderSimple, KSampler). Or query to search class names. Returns only matching nodes; no downloads.', inputSchema={
                    'type': 'object', 'properties': {'class_names': {'type': 'array', 'items': {'type': 'string'}}, 'query': {'type': 'string'}}, 'additionalProperties': False,
                    }),
                    Tool(name='server_info', description='Confirm that the selected local ComfyUI API is responsive and report its address.', inputSchema={'type': 'object', 'properties': {}, 'additionalProperties': False}),
                    Tool(name='system_stats', description='Read the selected ComfyUI instance\'s live system and VRAM statistics.', inputSchema={'type': 'object', 'properties': {}, 'additionalProperties': False}),
                    Tool(name='validate_workflow', description='Check an API-format ComfyUI workflow JSON file against the live node schemas. Connections must use ["node_id", output_index], for example ["1", 0]. This does not queue a run.', inputSchema={'type': 'object', 'properties': {'workflow_path': {'type': 'string'}}, 'required': ['workflow_path'], 'additionalProperties': False}),
                    Tool(name='run_workflow', description='Queue an API-format ComfyUI workflow JSON file on the selected local ComfyUI. Set wait true to return completed output details.', inputSchema={'type': 'object', 'properties': {'workflow_path': {'type': 'string'}, 'wait': {'type': 'boolean', 'default': True}, 'timeout_seconds': {'type': 'number', 'default': 110}}, 'required': ['workflow_path'], 'additionalProperties': False}),
                    Tool(name='job', description='Check, wait for, list or cancel jobs submitted through this AgentPort connection.', inputSchema={'type': 'object', 'properties': {'action': {'type': 'string', 'enum': ['status', 'wait', 'queue', 'cancel'], 'default': 'status'}, 'prompt_id': {'type': 'string'}, 'timeout_seconds': {'type': 'number', 'default': 110}}, 'additionalProperties': False}),
                    Tool(name='fetch_outputs', description='Return completed output metadata and local ComfyUI view URLs for a submitted job. No file download is needed for verification.', inputSchema={'type': 'object', 'properties': {'prompt_id': {'type': 'string'}}, 'required': ['prompt_id'], 'additionalProperties': False}),
                    Tool(name='free_memory', description='Ask the selected ComfyUI instance to unload models and clear executor memory after its current work finishes.', inputSchema={'type': 'object', 'properties': {'unload_models': {'type': 'boolean', 'default': True}, 'free_memory': {'type': 'boolean', 'default': True}}, 'additionalProperties': False}),
                ])
            names = {tool.name for tool in tools}
            server = Server("agentport-tools")

            @server.list_tools()
            async def list_tools():
                return tools

            @server.call_tool()
            async def call_tool(name, arguments):
                if name not in names:
                    raise ValueError("Tool is not enabled in this connection")
                if name == 'nodes' and comfy_url:
                    try:
                        async with httpx.AsyncClient(timeout=20, trust_env=False) as client:
                            classes = arguments.get('class_names', [])[:8]
                            if classes:
                                result = {}
                                for node in classes:
                                    response = await client.get(comfy_url.rstrip('/')+'/object_info/'+quote(node, safe=''))
                                    response.raise_for_status()
                                    result.update(response.json())
                                result = {'nodes': result, 'missing': [node for node in classes if node not in result]}
                            else:
                                response = await client.get(comfy_url.rstrip('/')+'/object_info')
                                response.raise_for_status()
                                query = arguments.get('query', '').lower()
                                candidates = [{'class_name': key, 'name': value.get('display_name', key)} for key,value in response.json().items() if query in (key+' '+value.get('display_name','')).lower()]
                                result = {'matches': candidates[:20], 'total': len(candidates)}
                            return CallToolResult(content=[TextContent(type='text', text=json.dumps(result))])
                    except Exception as error:
                        return CallToolResult(isError=True, content=[TextContent(type='text', text='ComfyUI node lookup failed: '+str(error))])
                if comfy_url and name in {'server_info', 'system_stats', 'validate_workflow', 'run_workflow', 'job', 'fetch_outputs', 'free_memory'}:
                    base = comfy_url.rstrip('/')
                    try:
                        async with httpx.AsyncClient(timeout=20, trust_env=False) as client:
                            if name == 'server_info':
                                stats = (await client.get(base + '/system_stats')).json()
                                result = {'server': {'running': True, 'url': base}, 'system': {'gpu': stats.get('devices', [{}])[0].get('name', 'unknown')}}
                            elif name == 'system_stats':
                                result = (await client.get(base + '/system_stats')).json()
                            elif name == 'free_memory':
                                payload = {'unload_models': arguments.get('unload_models', True), 'free_memory': arguments.get('free_memory', True)}
                                response = await client.post(base + '/free', json=payload); response.raise_for_status(); result = {'requested': payload}
                            elif name in {'validate_workflow', 'run_workflow'}:
                                workflow_path = Path(arguments['workflow_path'])
                                workflow = json.loads(workflow_path.read_text(encoding='utf-8'))
                                if not isinstance(workflow, dict) or not workflow:
                                    raise ValueError('Workflow must be a non-empty API-format JSON object.')
                                errors = []
                                schemas = {}
                                for node_id, node in workflow.items():
                                    if not isinstance(node, dict) or not node.get('class_type'):
                                        errors.append({'node_id': node_id, 'message': 'Each API node needs class_type.'}); continue
                                    response = await client.get(base + '/object_info/' + quote(str(node['class_type']), safe=''))
                                    if response.status_code != 200:
                                        errors.append({'node_id': node_id, 'message': 'Unknown node class '+str(node['class_type'])})
                                        continue
                                    schema_payload = response.json()
                                    schemas[str(node_id)] = schema_payload.get(str(node['class_type']), schema_payload)
                                for node_id, node in workflow.items():
                                    if not isinstance(node, dict) or str(node_id) not in schemas:
                                        continue
                                    inputs = node.get('inputs', {})
                                    if not isinstance(inputs, dict):
                                        errors.append({'node_id': node_id, 'message': 'inputs must be a JSON object.'})
                                        continue
                                    required = schemas[str(node_id)].get('input', {}).get('required', {})
                                    for field in required:
                                        if field not in inputs:
                                            errors.append({'node_id': node_id, 'field': field, 'message': 'Required input is missing.'})
                                    for field, value in inputs.items():
                                        spec = required.get(field)
                                        expected = spec[0] if isinstance(spec, list) and spec else None
                                        if isinstance(value, dict) and isinstance(expected, str) and expected.isupper():
                                            errors.append({'node_id': node_id, 'field': field, 'message': 'Connections must use ["node_id", output_index], not an object.'})
                                        if isinstance(value, list) and len(value) == 2:
                                            source_id = value[0]
                                            if not isinstance(source_id, str):
                                                errors.append({'node_id': node_id, 'field': field, 'message': 'Node links must use string node IDs, for example ["1", 0].'})
                                            elif source_id not in workflow:
                                                errors.append({'node_id': node_id, 'field': field, 'message': 'Link refers to missing node '+source_id})
                                            if not isinstance(value[1], int) or value[1] < 0:
                                                errors.append({'node_id': node_id, 'field': field, 'message': 'A node link output index must be a non-negative integer.'})
                                if name == 'validate_workflow':
                                    result = {'workflow': str(workflow_path), 'valid': not errors, 'errors': errors, 'warnings': []}
                                elif errors:
                                    result = {'queued': False, 'errors': errors}
                                else:
                                    response = await client.post(base + '/prompt', json={'prompt': workflow, 'client_id': 'agentport-mcp'})
                                    if response.is_error:
                                        raise RuntimeError('ComfyUI rejected the workflow: ' + response.text)
                                    submitted = response.json(); prompt_id = submitted.get('prompt_id')
                                    result = {'queued': True, 'prompt_id': prompt_id, 'number': submitted.get('number')}
                                    if arguments.get('wait', True):
                                        deadline = asyncio.get_running_loop().time() + min(float(arguments.get('timeout_seconds', 110)), 3600)
                                        while asyncio.get_running_loop().time() < deadline:
                                            history = (await client.get(base + '/history/' + quote(str(prompt_id), safe=''))).json()
                                            item = history.get(str(prompt_id)) if isinstance(history, dict) else None
                                            if item:
                                                status = item.get('status', {})
                                                if status.get('status_str') == 'error':
                                                    raise RuntimeError('ComfyUI execution failed: ' + json.dumps(status.get('messages', [])))
                                                if status.get('completed'):
                                                    result['completed'] = True; result['history'] = item; break
                                            await asyncio.sleep(0.5)
                                        else: result['completed'] = False; result['timed_out'] = True
                            elif name == 'job':
                                action = arguments.get('action', 'status')
                                if action == 'queue': result = (await client.get(base + '/queue')).json()
                                elif action == 'cancel':
                                    response = await client.post(base + '/interrupt', json={}); response.raise_for_status(); result = {'cancel_requested': True, 'prompt_id': arguments.get('prompt_id')}
                                else:
                                    prompt_id = arguments.get('prompt_id')
                                    if not prompt_id: raise ValueError('prompt_id is required for job status or wait.')
                                    deadline = asyncio.get_running_loop().time() + min(float(arguments.get('timeout_seconds', 110)), 3600)
                                    while True:
                                        history = (await client.get(base + '/history/' + quote(str(prompt_id), safe=''))).json()
                                        item = history.get(str(prompt_id)) if isinstance(history, dict) else None
                                        status = (item or {}).get('status', {})
                                        completed = bool(status.get('completed'))
                                        failed = status.get('status_str') == 'error'
                                        if action == 'status' or completed or failed or asyncio.get_running_loop().time() >= deadline:
                                            result = {'prompt_id': prompt_id, 'completed': completed, 'failed': failed, 'history': item}; break
                                        await asyncio.sleep(0.5)
                            else:  # fetch_outputs
                                prompt_id = arguments['prompt_id']; history = (await client.get(base + '/history/' + quote(str(prompt_id), safe=''))).json()
                                item = history.get(str(prompt_id)) if isinstance(history, dict) else None
                                outputs = []
                                for node_id, output in (item or {}).get('outputs', {}).items():
                                    for image in output.get('images', []):
                                        query = '&'.join(f'{key}={quote(str(value))}' for key, value in image.items() if key in {'filename', 'subfolder', 'type'})
                                        outputs.append({'node_id': node_id, **image, 'url': base + '/view?' + query})
                                status = (item or {}).get('status', {})
                                result = {'prompt_id': prompt_id, 'completed': bool(status.get('completed')), 'failed': status.get('status_str') == 'error', 'outputs': outputs}
                        return CallToolResult(content=[TextContent(type='text', text=json.dumps(result))])
                    except Exception as error:
                        return CallToolResult(isError=True, content=[TextContent(type='text', text='ComfyUI API call failed: '+str(error))])
                return await session.call_tool(name, arguments)

            async with stdio_server() as transport:
                await server.run(*transport, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
