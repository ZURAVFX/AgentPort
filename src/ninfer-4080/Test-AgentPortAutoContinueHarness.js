'use strict';
// Real Harness integration against deterministic OpenAI streaming responses.
// Uses its own DSH_HOME and random loopback ports; never edits user settings.
const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');
const { randomUUID } = require('crypto');
const assert = require('assert/strict');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const calls = new Map();
let child, server, log = '';
async function until(fn, timeout = 15000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { const value = await fn(); if (value) return value; await sleep(100); }
  throw Error('Timed out waiting for integration condition');
}
async function main() {
  const entry = path.resolve(process.argv[2]);
  const root = path.resolve(process.argv[3] || 'outputs/auto-continue-test-' + Date.now());
  fs.mkdirSync(root, { recursive: true });
  const options = path.join(root, 'auto-continue.json');
  const setOptions = (enabled, maxContinuations = 2) => fs.writeFileSync(options, JSON.stringify({ enabled, maxContinuations }));
  setOptions(false);
  server = http.createServer(async (req, res) => {
    if (req.url === '/v1/models') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ data: [{ id: 'auto-test' }] })); return; }
    let body = ''; for await (const part of req) body += part;
    const input = JSON.parse(body);
    const all = JSON.stringify(input.messages);
    const marker = /CASE_[A-Z]+_[a-z0-9-]+/.exec(all)?.[0];
    if (!marker) { res.writeHead(400); res.end('Missing test marker'); return; }
    const count = (calls.get(marker) || 0) + 1; calls.set(marker, count);
    if (marker.startsWith('CASE_ERROR_')) { res.writeHead(500); res.end('Intentional test error'); return; }
    const truncated = marker.startsWith('CASE_LIMIT_') || count === 1;
    const content = truncated ? 'Partial reply' : 'DONE';
    const finish = truncated ? 'length' : 'stop';
    if (input.stream) {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      for (const choice of [{ delta: { role: 'assistant', content }, finish_reason: null }, { delta: {}, finish_reason: finish }]) {
        res.write('data: ' + JSON.stringify({ id: 'chatcmpl-test', object: 'chat.completion.chunk', created: 1, model: 'auto-test', choices: [{ index: 0, ...choice }] }) + '\n\n');
      }
      res.end('data: [DONE]\n\n');
    } else { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content }, finish_reason: finish }] })); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const portProbe = http.createServer();
  await new Promise(resolve => portProbe.listen(0, '127.0.0.1', resolve));
  const webPort = portProbe.address().port;
  await new Promise(resolve => portProbe.close(resolve));
  const settings = {
    'llm-pi-ai': { providers: { 'auto-test': { displayName: 'Test', apiKeyEnv: 'AGENTPORT_TEST_KEY', api: 'openai-completions', baseURL: `http://127.0.0.1:${server.address().port}/v1`, defaultInput: ['text'], retryPolicy: { mode: 'normal', maxRetries: 0 }, models: [{ id: 'auto-test', name: 'Test', contextWindow: 65536, maxTokens: 32 }] } } },
    'agent-default-model': { provider: 'auto-test', model: 'auto-test' }
  };
  fs.writeFileSync(path.join(root, 'settings.yaml'), JSON.stringify(settings));
  const patch = path.join(root, 'test.patch.json');
  fs.writeFileSync(patch, JSON.stringify([
    { id: 'webserver', config: { host: '127.0.0.1', port: webPort } },
    { id: 'session-title-llm', disabled: true },
    { insert: [{ id: 'agentport-auto-continue', name: path.join(__dirname, 'AgentPort.AutoContinue.js'), config: { settingsPath: options } }] }
  ]));
  child = spawn(process.execPath, [entry, 'web', '--patch', patch, '--no-open'], { cwd: root, windowsHide: true, env: { ...process.env, DSH_HOME: root, AGENTPORT_TEST_KEY: 'test', DSH_TELEMETRY_DISABLED: '1' }, stdio: ['ignore', 'pipe', 'pipe'] });
  child.stdout.on('data', b => { log += b; }); child.stderr.on('data', b => { log += b; });
  const url = await until(() => /dsh web:\s+(http:\/\/127\.0\.0\.1:\d+\/\?token=[A-Za-z0-9_-]+)/.exec(log)?.[1], 45000);
  const base = new URL(url).origin;
  const auth = await fetch(url, { redirect: 'manual' });
  const cookie = auth.headers.getSetCookie().map(c => c.split(';')[0]).join('; ');
  assert(cookie, 'Harness must issue an authenticated cookie');
  async function rpc(method, request, wire = 'request') {
    const response = await fetch(base + '/api/' + method, { method: 'POST', headers: { 'Content-Type': 'application/json', Cookie: cookie }, body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method, payload: { args: { [wire]: request } } }) });
    const value = await response.json();
    if (!value.result.ok) throw Error(method + ': ' + value.result.error.message);
    return value.result.value;
  }
  async function start(kind) {
    const { sessionId } = await rpc('session/create', {});
    const marker = 'CASE_' + kind + '_' + randomUUID();
    await rpc('session/prompt', { sessionId, requestId: randomUUID(), mode: 'queue', content: [{ type: 'text', text: marker + ': respond; no tools.' }] });
    await until(() => calls.has(marker));
    return { sessionId, marker };
  }
  let test = await start('OFF'); await sleep(3000); assert.equal(calls.get(test.marker), 1); console.log('PASS disabled: no continuation');
  setOptions(true);
  test = await start('ON'); await until(() => calls.get(test.marker) === 2); await sleep(2500); assert.equal(calls.get(test.marker), 2); console.log('PASS output limit resumes once; normal completion stops');
  test = await start('LIMIT'); await until(() => calls.get(test.marker) === 3); await sleep(2500); assert.equal(calls.get(test.marker), 3); console.log('PASS continuation cap enforced');
  test = await start('CANCEL'); await sleep(200); await rpc('session/cancel', { sessionId: test.sessionId }); await sleep(3000); assert.equal(calls.get(test.marker), 1); console.log('PASS explicit Stop cancels pending continuation');
  test = await start('DISABLE'); setOptions(false); await sleep(3000); assert.equal(calls.get(test.marker), 1); console.log('PASS switching off cancels pending continuation');
  setOptions(true);
  test = await start('ERROR'); await sleep(3000); assert.equal(calls.get(test.marker), 1); console.log('PASS backend error is not auto-retried');
  fs.writeFileSync(path.join(root, 'result.txt'), 'All real Harness auto-continuation checks passed.\n');
}
main().catch(error => { console.error(error.message); console.error(log.replace(/token=[A-Za-z0-9_-]+/g, 'token=[redacted]').slice(-6000)); process.exitCode = 1; }).finally(async () => {
  if (child && child.exitCode === null) { child.kill(); await Promise.race([new Promise(resolve => child.once('exit', resolve)), sleep(5000)]); }
  if (server) { server.closeAllConnections(); server.close(); }
});
