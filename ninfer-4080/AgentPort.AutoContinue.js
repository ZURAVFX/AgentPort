'use strict'

// Optional AgentPort continuation for a Harness turn that genuinely reached
// the model output limit.  This is deliberately a local CommonJS plugin: the
// packaged AgentPort runtime mounts it by absolute path and it must not depend
// on the Harness package layout or on any bare module import.
const fs = require('node:fs')
const path = require('node:path')
const { randomUUID } = require('node:crypto')

const name = 'agentport-auto-continue'
const inject = ['agents']
const RPC_PREFIX = 'agentport-auto-continue-'
const CONTINUE_DELAY_MS = 1500
const DEFAULT_MAX_CONTINUATIONS = 10
const MIN_MAX_CONTINUATIONS = 1
const MAX_MAX_CONTINUATIONS = 50
const END_HISTORY_LIMIT = 64

/**
 * Freeze the small message graph before it crosses the plugin boundary.
 * Harness UserMessage also requires an identity; use the same UUID as the
 * source correlation suffix so every follow-up is independently identifiable.
 */
function createUserMessage(text) {
  const uuid = randomUUID()
  const contentBlock = Object.freeze({ type: 'text', text: String(text) })
  const content = Object.freeze([contentBlock])
  const source = Object.freeze({ kind: 'user', rpcId: RPC_PREFIX + uuid })
  return Object.freeze({
    id: uuid,
    role: 'user',
    content,
    source,
  })
}

function normalizeOptions(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return { enabled: false, maxContinuations: DEFAULT_MAX_CONTINUATIONS }
  }

  if (value.enabled !== true && value.enabled !== false) {
    return { enabled: false, maxContinuations: DEFAULT_MAX_CONTINUATIONS }
  }

  let maxContinuations = DEFAULT_MAX_CONTINUATIONS
  if (Object.prototype.hasOwnProperty.call(value, 'maxContinuations')) {
    if (!Number.isSafeInteger(value.maxContinuations)
      || value.maxContinuations < MIN_MAX_CONTINUATIONS
      || value.maxContinuations > MAX_MAX_CONTINUATIONS) {
      return { enabled: false, maxContinuations: DEFAULT_MAX_CONTINUATIONS }
    }
    maxContinuations = value.maxContinuations
  }

  return {
    enabled: value.enabled === true,
    maxContinuations,
  }
}

/** Read the file on every decision, so a UI toggle takes effect in-place. */
function readOptions(settingsPath) {
  if (typeof settingsPath !== 'string' || settingsPath.length === 0) {
    return normalizeOptions(undefined)
  }
  try {
    return normalizeOptions(JSON.parse(fs.readFileSync(settingsPath, 'utf8')))
  }
  catch {
    // A missing or partially-written options file is fail-closed.  The next
    // event/timer poll will re-read it without taking down the Harness host.
    return normalizeOptions(undefined)
  }
}

function sessionHeader(session) {
  if (session === null || typeof session !== 'object') return undefined
  if (session.header !== null && typeof session.header === 'object') return session.header
  if (session.meta !== null && typeof session.meta === 'object') return session.meta
  return session
}

/**
 * Only top-level sessions are eligible.  The durable parent/origin/depth
 * markers are checked together with the small fixture-friendly meta fallback.
 */
function isRootSession(session) {
  const header = sessionHeader(session)
  if (header === undefined) return true
  if (header.parentSession !== undefined) return false
  if (header.origin === 'subagent') return false
  if (Number.isSafeInteger(header.delegationDepth) && header.delegationDepth > 0) return false
  if (header.meta && typeof header.meta === 'object') {
    if (header.meta.origin === 'subagent') return false
    if (Number.isSafeInteger(header.meta.delegationDepth) && header.meta.delegationDepth > 0) return false
  }
  return true
}

function isAutoMessage(message) {
  const source = message && message.source
  return source !== null
    && typeof source === 'object'
    && source.kind === 'user'
    && typeof source.rpcId === 'string'
    && source.rpcId.startsWith(RPC_PREFIX)
}

function isHumanMessage(message) {
  const source = message && message.source
  return source !== null
    && typeof source === 'object'
    && source.kind === 'user'
    && !isAutoMessage(message)
}

function queuedLength(value) {
  return value !== null && value !== undefined && Number.isFinite(value.length)
    ? Math.max(0, value.length)
    : 0
}

function hasQueuedInput(agent) {
  const inbox = agent && agent.inbox
  if (inbox === null || typeof inbox !== 'object') return false
  return queuedLength(inbox.nextTurn) > 0 || queuedLength(inbox.nextStep) > 0
}

function stateIsIdle(state) {
  if (state.status !== undefined) return state.status === 'idle'
  return state.agent && state.agent.status === 'idle'
}

function sessionIdentity(session) {
  if (session && session.id !== undefined) return String(session.id)
  const header = sessionHeader(session)
  if (header && header.id !== undefined) return String(header.id)
  return ''
}

function endIdentity(state, session, event) {
  const prefix = sessionIdentity(session)
  if (event && event.seq !== undefined) return `${prefix}:seq:${String(event.seq)}`
  const turn = event && event.data && event.data.turn
  if (turn !== undefined) return `${prefix}:turn:${String(turn)}`
  return undefined
}

function forgetPending(state) {
  if (state.pending !== undefined) {
    clearTimeout(state.pending.timer)
    state.pending = undefined
  }
  state.latestEnd = undefined
}

function forgetRequest(state) {
  forgetPending(state)
  state.generation += 1
  state.continuationCount = 0
  state.hasHumanRequest = false
  state.activeTurn = undefined
  state.lastHumanMessage = undefined
  state.lastHumanId = undefined
  state.seenEndKeys.clear()
  state.seenEndOrder.length = 0
  state.seenEndObjects = new WeakSet()
}

function rememberHumanMessage(state, message) {
  if (!isHumanMessage(message)) return
  const id = message && message.id
  if (message === state.lastHumanMessage || (id !== undefined && id === state.lastHumanId)) return
  forgetPending(state)
  state.generation += 1
  state.continuationCount = 0
  state.hasHumanRequest = true
  state.lastHumanMessage = message
  state.lastHumanId = id
  state.seenEndKeys.clear()
  state.seenEndOrder.length = 0
  state.seenEndObjects = new WeakSet()
}

function restoreCancel(state) {
  const { agent, cancelWrapper } = state
  if (cancelWrapper === undefined || state.cancelOriginal === undefined) return
  let current
  try { current = agent.cancel } catch { return }
  if (current !== cancelWrapper) return
  try {
    if (state.cancelDescriptor === undefined) delete agent.cancel
    else Object.defineProperty(agent, 'cancel', state.cancelDescriptor)
  }
  catch {
    // Disposal must not mask the Harness's own shutdown path.
  }
  state.cancelWrapper = undefined
}

function installCancelWrapper(state) {
  const agent = state.agent
  if (state.cancelReady !== undefined || state.cancelWrapper !== undefined || agent === null || typeof agent.cancel !== 'function') {
    if (state.cancelReady === undefined) state.cancelReady = false
    return
  }
  const original = agent.cancel
  const descriptor = Object.getOwnPropertyDescriptor(agent, 'cancel')
  const wrapper = function wrappedAgentPortCancel(...args) {
    // Agent.cancel intentionally has no lifecycle event on an idle agent.  The
    // wrapper closes the exact race where Stop lands during our delay while
    // preserving the original receiver, arguments, return value, and throw.
    forgetPending(state)
    return Reflect.apply(original, this, args)
  }
  try {
    agent.cancel = wrapper
    if (agent.cancel !== wrapper) {
      state.cancelReady = false
      return
    }
  }
  catch {
    state.cancelReady = false
    return
  }
  state.cancelOriginal = original
  state.cancelDescriptor = descriptor
  state.cancelWrapper = wrapper
  state.cancelReady = true
}

function disposeState(state) {
  if (state.disposed) return
  state.disposed = true
  forgetPending(state)
  restoreCancel(state)
}

function isCurrentAgent(ctx, state) {
  const current = ctx
    && ctx.agents
    && typeof ctx.agents.get === 'function'
    ? ctx.agents.get(state.session && state.session.id)
    : state.agent
  if (current !== state.agent) return false
  if (state.agent.session !== undefined && state.session !== undefined && state.agent.session !== state.session) return false
  return true
}

function addEndIdentity(state, event, key) {
  if (key !== undefined) {
    if (state.seenEndKeys.has(key)) return false
    state.seenEndKeys.add(key)
    state.seenEndOrder.push(key)
    while (state.seenEndOrder.length > END_HISTORY_LIMIT) {
      state.seenEndKeys.delete(state.seenEndOrder.shift())
    }
    return true
  }
  if (event === null || typeof event !== 'object') return false
  if (state.seenEndObjects.has(event)) return false
  state.seenEndObjects.add(event)
  return true
}

function scheduleContinuation(ctx, state, session, event, settingsPath) {
  if (state.disposed || !state.hasHumanRequest || state.cancelReady !== true || !isRootSession(session)) return
  const data = event && event.data
  if (data === null || typeof data !== 'object' || data.reason === null || typeof data.reason !== 'object') return
  if (data.reason.kind !== 'max-tokens') {
    // completed, aborted, error, permission, and context failures are all
    // terminal for this optional feature.
    forgetPending(state)
    return
  }

  const activeTurn = state.activeTurn
  if (activeTurn === undefined || activeTurn.turn !== data.turn || activeTurn.generation !== state.generation) {
    forgetPending(state)
    return
  }

  const options = readOptions(settingsPath)
  if (!options.enabled || state.continuationCount >= options.maxContinuations) {
    forgetPending(state)
    return
  }

  const key = endIdentity(state, session, event)
  if (!addEndIdentity(state, event, key)) return
  forgetPending(state)
  const pending = {
    generation: state.generation,
    key,
    event,
    timer: undefined,
  }
  pending.timer = setTimeout(() => runContinuation(ctx, state, session, pending, settingsPath), CONTINUE_DELAY_MS)
  state.pending = pending
  state.latestEnd = pending
}

function runContinuation(ctx, state, session, pending, settingsPath) {
  if (state.disposed || state.pending !== pending) return
  state.pending = undefined

  if (state.generation !== pending.generation || state.latestEnd !== pending) return
  if (pending.event !== state.latestEnd.event || pending.key !== state.latestEnd.key) return
  if (state.cancelReady !== true || state.agent.cancel !== state.cancelWrapper) return
  if (!isRootSession(session) || !isCurrentAgent(ctx, state) || !stateIsIdle(state)) return
  if (hasQueuedInput(state.agent)) return

  const options = readOptions(settingsPath)
  if (!options.enabled || state.continuationCount >= options.maxContinuations) return

  const count = state.continuationCount + 1
  const prompt = `[AgentPort auto-continue ${count}/${options.maxContinuations}] The reply reached its output limit. Continue the existing request from where you stopped. Do not repeat finished work or broaden the task. Stop when complete.`
  const message = createUserMessage(prompt)
  try {
    state.agent.followup(message)
  }
  catch {
    // A concurrent disposal/cancel wins.  Do not retry an unknown followup
    // failure or turn a backend lifecycle error into recursion.
    return
  }
  state.continuationCount = count
}

function makeState(agent, session) {
  const state = {
    agent,
    session: session === undefined ? agent.session : session,
    status: agent && agent.status,
    generation: 0,
    continuationCount: 0,
    hasHumanRequest: false,
    activeTurn: undefined,
    lastHumanMessage: undefined,
    lastHumanId: undefined,
    pending: undefined,
    latestEnd: undefined,
    seenEndKeys: new Set(),
    seenEndOrder: [],
    seenEndObjects: new WeakSet(),
    cancelOriginal: undefined,
    cancelDescriptor: undefined,
    cancelWrapper: undefined,
    cancelReady: undefined,
    disposed: false,
  }
  return state
}

function apply(ctx, config) {
  const settingsPath = config && typeof config.settingsPath === 'string'
    ? path.resolve(config.settingsPath)
    : ''
  const statesByAgent = new WeakMap()
  const liveStates = new Set()
  let disposed = false

  function stateFor(agent, session) {
    if (disposed || agent === null || typeof agent !== 'object') return undefined
    let state = statesByAgent.get(agent)
    if (state === undefined || state.disposed) {
      state = makeState(agent, session)
      statesByAgent.set(agent, state)
      liveStates.add(state)
    }
    else if (session !== undefined && state.session !== session) {
      // A registry replacement must never inherit an old request's count.
      forgetRequest(state)
      state.session = session
      state.status = agent.status
    }
    installCancelWrapper(state)
    return state
  }

  function onAgentCreated(agent) {
    if (agent !== undefined) stateFor(agent, agent.session)
  }

  function onAgentDisposed(agent) {
    if (agent === undefined) return
    const state = statesByAgent.get(agent)
    if (state === undefined) return
    disposeState(state)
    statesByAgent.delete(agent)
    liveStates.delete(state)
  }

  if (ctx && ctx.agents && typeof ctx.agents.list === 'function') {
    for (const agent of ctx.agents.list()) onAgentCreated(agent)
  }

  ctx.on('agent/created', ({ agent }) => onAgentCreated(agent))
  ctx.on('agent/disposed', ({ agent }) => onAgentDisposed(agent))
  ctx.on('agent/status', ({ agent, status }) => {
    const state = stateFor(agent, agent && agent.session)
    if (state !== undefined) state.status = status
  })
  ctx.on('agent/inbox/inserted', ({ agent, message }) => {
    const state = stateFor(agent, agent && agent.session)
    if (state !== undefined) rememberHumanMessage(state, message)
  })
  ctx.on('agent/error', ({ agent }) => {
    const state = stateFor(agent, agent && agent.session)
    if (state !== undefined) forgetRequest(state)
  })
  ctx.on('session/event', (session, event) => {
    if (session === null || typeof session !== 'object' || event === null || typeof event !== 'object') return
    const agent = ctx.agents && typeof ctx.agents.get === 'function'
      ? ctx.agents.get(session.id)
      : undefined
    if (agent === undefined || (agent.session !== undefined && agent.session !== session)) return
    const state = stateFor(agent, session)
    if (state === undefined || state.disposed) return

    if (event.type === 'user/message') {
      if (isAutoMessage(event.data)) return
      rememberHumanMessage(state, event.data)
      return
    }
    if (event.type === 'turn/start') {
      const turn = event.data && event.data.turn
      if (Number.isSafeInteger(turn)) {
        state.activeTurn = { turn, generation: state.generation }
      }
      return
    }
    if (event.type === 'turn/end') {
      scheduleContinuation(ctx, state, session, event, settingsPath)
    }
  })

  if (ctx && typeof ctx.effect === 'function') {
    ctx.effect(() => () => {
      if (disposed) return
      disposed = true
      for (const state of liveStates) disposeState(state)
      liveStates.clear()
    }, `${name}: cleanup`)
  }
}

module.exports = {
  name,
  inject,
  apply,
  // Kept non-public by convention, but useful for the isolated Node test and
  // harmless to the Cordis loader.
  _testing: {
    createUserMessage,
    normalizeOptions,
    readOptions,
    isRootSession,
    isAutoMessage,
  },
}
