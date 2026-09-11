'use strict'

// Isolated unit coverage for AgentPort.AutoContinue.js.  This uses only Node's
// built-ins and a deterministic timer shim, so it never starts Harness or
// touches the user's DSH_HOME/configuration.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { randomUUID } = require('node:crypto')
const plugin = require('./AgentPort.AutoContinue.js')

const realSetTimeout = global.setTimeout
const realClearTimeout = global.clearTimeout
const scheduled = []
let timerId = 0

global.setTimeout = (callback, delay) => {
  const timer = { id: ++timerId, callback, delay, active: true }
  scheduled.push(timer)
  return timer
}
global.clearTimeout = timer => {
  if (timer !== undefined && timer !== null) timer.active = false
}

function flushTimers() {
  const pending = scheduled.splice(0, scheduled.length)
  for (const timer of pending) {
    if (timer.active) timer.callback()
  }
}

class FakeContext {
  constructor(agent) {
    this.listeners = new Map()
    this.currentAgent = agent
    this.agents = {
      list: () => this.currentAgent === undefined ? [] : [this.currentAgent],
      get: id => this.currentAgent !== undefined && this.currentAgent.id === id ? this.currentAgent : undefined,
    }
    this.cleanup = undefined
  }

  on(name, listener) {
    const listeners = this.listeners.get(name) || []
    listeners.push(listener)
    this.listeners.set(name, listeners)
    return () => {
      const current = this.listeners.get(name) || []
      this.listeners.set(name, current.filter(item => item !== listener))
    }
  }

  emit(name, ...args) {
    for (const listener of [...(this.listeners.get(name) || [])]) listener(...args)
  }

  effect(factory) {
    const cleanup = factory()
    this.cleanup = typeof cleanup === 'function' ? cleanup : undefined
    return () => {
      if (this.cleanup !== undefined) this.cleanup()
      this.cleanup = undefined
    }
  }

  dispose() {
    if (this.cleanup !== undefined) this.cleanup()
    this.cleanup = undefined
  }
}

function writeOptions(file, enabled, maxContinuations = 10) {
  fs.writeFileSync(file, JSON.stringify({ enabled, maxContinuations }))
}

function makeCase({ enabled = false, maxContinuations = 10, subagent = false, readonlyCancel = false } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agentport-auto-continue-'))
  const optionsPath = path.join(root, 'options.json')
  writeOptions(optionsPath, enabled, maxContinuations)
  const session = {
    id: 'session-' + randomUUID(),
    header: subagent
      ? { id: 'subagent', parentSession: 'root', origin: 'subagent', delegationDepth: 1 }
      : { id: 'root' },
  }
  const followups = []
  const cancelCalls = []
  const agent = {
    id: session.id,
    session,
    status: 'idle',
    inbox: { nextTurn: [], nextStep: [] },
    followup(message) { followups.push(message) },
    cancel(...args) {
      cancelCalls.push(args)
      return 'cancel-result'
    },
  }
  if (readonlyCancel) {
    Object.defineProperty(agent, 'cancel', { value: agent.cancel, writable: false, configurable: false })
  }
  const ctx = new FakeContext(agent)
  plugin.apply(ctx, { settingsPath: optionsPath })
  ctx.emit('agent/status', { agent, status: 'idle' })
  let seq = 0
  return {
    root,
    optionsPath,
    session,
    agent,
    ctx,
    followups,
    cancelCalls,
    user(id = randomUUID(), rpcId) {
      const data = {
        id,
        role: 'user',
        content: [{ type: 'text', text: 'human request' }],
        source: { kind: 'user', ...(rpcId === undefined ? {} : { rpcId }) },
      }
      ctx.emit('session/event', session, { type: 'user/message', seq: ++seq, data })
      return data
    },
    end(kind = 'max-tokens', turn = ++seq) {
      ctx.emit('session/event', session, { type: 'turn/start', seq: ++seq, data: { turn } })
      const event = { type: 'turn/end', seq: ++seq, data: { turn, reason: { kind } } }
      ctx.emit('session/event', session, event)
      return event
    },
    setOptions(nextEnabled, nextMax = maxContinuations) {
      writeOptions(optionsPath, nextEnabled, nextMax)
    },
    dispose() {
      ctx.emit('agent/disposed', { agent })
      ctx.dispose()
      fs.rmSync(root, { recursive: true, force: true })
    },
  }
}

function run() {
  assert.equal(plugin.name, 'agentport-auto-continue')
  assert.deepEqual(plugin.inject, ['agents'])

  const message = plugin._testing.createUserMessage('hello')
  assert.equal(message.role, 'user')
  assert.deepEqual(message.content, [{ type: 'text', text: 'hello' }])
  assert.equal(message.source.kind, 'user')
  assert.match(message.source.rpcId, /^agentport-auto-continue-/)
  assert.ok(Object.isFrozen(message))
  assert.ok(Object.isFrozen(message.content))
  assert.ok(Object.isFrozen(message.content[0]))
  assert.ok(Object.isFrozen(message.source))

  {
    const test = makeCase()
    test.user()
    test.end()
    flushTimers()
    assert.equal(test.followups.length, 0, 'disabled by default')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true, maxContinuations: 2 })
    test.user()
    const firstEnd = test.end()
    test.ctx.emit('session/event', test.session, firstEnd)
    flushTimers()
    assert.equal(test.followups.length, 1, 'one enabled continuation')
    assert.equal(test.followups[0].content[0].text, '[AgentPort auto-continue 1/2] The reply reached its output limit. Continue the existing request from where you stopped. Do not repeat finished work or broaden the task. Stop when complete.')
    assert.equal(test.followups[0].role, 'user')
    assert.match(test.followups[0].source.rpcId, /^agentport-auto-continue-/)
    test.end('completed', 2)
    flushTimers()
    assert.equal(test.followups.length, 1, 'normal completion does not continue')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true, maxContinuations: 2 })
    test.user()
    test.end('max-tokens', 1)
    flushTimers()
    test.end('max-tokens', 2)
    flushTimers()
    test.end('max-tokens', 3)
    flushTimers()
    assert.equal(test.followups.length, 2, 'continuation cap is per human request')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true })
    test.user('human-a')
    test.end()
    test.user('human-b')
    flushTimers()
    assert.equal(test.followups.length, 0, 'real user insertion cancels pending continuation')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true })
    test.user()
    test.end()
    const result = test.agent.cancel({ kind: 'user' }, { keepInbox: true })
    flushTimers()
    assert.equal(result, 'cancel-result', 'cancel return value is preserved')
    assert.deepEqual(test.cancelCalls, [[{ kind: 'user' }, { keepInbox: true }]], 'cancel arguments are preserved')
    assert.equal(test.followups.length, 0, 'idle cancel wins the pending timer race')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true, readonlyCancel: true })
    test.user()
    test.end()
    flushTimers()
    assert.equal(test.followups.length, 0, 'read-only cancel cannot be made safe, so auto-continue stays off')
    test.dispose()
  }

  {
    for (const kind of ['completed', 'aborted', 'error', 'permission', 'context']) {
      const test = makeCase({ enabled: true })
      test.user()
      test.end(kind)
      flushTimers()
      assert.equal(test.followups.length, 0, `${kind} is not auto-continued`)
      test.dispose()
    }
  }

  {
    const test = makeCase({ enabled: true })
    test.user()
    test.agent.inbox.nextTurn.push({ id: 'queued' })
    test.end()
    flushTimers()
    assert.equal(test.followups.length, 0, 'queued input prevents continuation')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true })
    test.user()
    test.end()
    const queued = {
      id: 'queued-human',
      role: 'user',
      content: [{ type: 'text', text: 'queued human request' }],
      source: { kind: 'user' },
    }
    test.agent.inbox.nextTurn.push(queued)
    test.ctx.emit('agent/inbox/inserted', { agent: test.agent, message: queued })
    test.agent.inbox.nextTurn.pop()
    flushTimers()
    assert.equal(test.followups.length, 0, 'queued human insertion invalidates a stale timer even if removed')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true })
    test.user()
    test.ctx.emit('session/event', test.session, { type: 'turn/start', seq: 1, data: { turn: 1 } })
    const queued = {
      id: 'queued-before-old-end',
      role: 'user',
      content: [{ type: 'text', text: 'queued during old turn' }],
      source: { kind: 'user' },
    }
    test.agent.inbox.nextTurn.push(queued)
    test.ctx.emit('agent/inbox/inserted', { agent: test.agent, message: queued })
    test.agent.inbox.nextTurn.pop()
    test.ctx.emit('session/event', test.session, {
      type: 'turn/end',
      seq: 2,
      data: { turn: 1, reason: { kind: 'max-tokens' } },
    })
    flushTimers()
    assert.equal(test.followups.length, 0, 'old turn cannot continue after queued input changed generation')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true })
    test.user()
    test.end()
    test.ctx.emit('agent/error', { agent: test.agent, turn: 1, step: 0, error: new Error('test') })
    flushTimers()
    assert.equal(test.followups.length, 0, 'agent errors disarm a pending continuation')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true, subagent: true })
    test.user()
    test.end()
    flushTimers()
    assert.equal(test.followups.length, 0, 'subagent sessions are excluded')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true })
    test.user()
    test.end()
    test.setOptions(false)
    flushTimers()
    assert.equal(test.followups.length, 0, 'reload disables a pending continuation')
    test.dispose()
  }

  {
    const test = makeCase({ enabled: true })
    test.user()
    test.end()
    test.dispose()
    flushTimers()
    assert.equal(test.followups.length, 0, 'dispose cancels pending continuation')
    assert.equal(test.agent.cancel({ kind: 'user' }), 'cancel-result', 'dispose restores original cancel')
  }

  {
    assert.deepEqual(plugin._testing.normalizeOptions({ enabled: true, maxContinuations: 0 }), { enabled: false, maxContinuations: 10 })
    assert.deepEqual(plugin._testing.normalizeOptions({ enabled: true, maxContinuations: 500 }), { enabled: false, maxContinuations: 10 })
    assert.deepEqual(plugin._testing.normalizeOptions({ enabled: 'yes', maxContinuations: '3' }), { enabled: false, maxContinuations: 10 })
  }
}

try {
  run()
  console.log('AgentPort.AutoContinue unit tests passed.')
}
finally {
  global.setTimeout = realSetTimeout
  global.clearTimeout = realClearTimeout
}
