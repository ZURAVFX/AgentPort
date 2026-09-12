'use strict';

// Structural settings writer for AgentPort. The PowerShell UI owns the
// operation selection; this file owns YAML parsing, duplicate-key repair and
// the validated atomic replacement. It deliberately never prints settings
// content because the file may contain user configuration or credentials.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function fail(message) {
  process.stderr.write(String(message) + '\n');
  process.exitCode = 1;
}

function isObject(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function deepEqual(left, right) {
  if (left === right) return true;
  if (typeof left !== typeof right || left === null || right === null) return false;
  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) return false;
    for (let index = 0; index < left.length; index += 1) {
      if (!deepEqual(left[index], right[index])) return false;
    }
    return true;
  }
  if (!isObject(left) || !isObject(right)) return false;
  const leftKeys = Object.keys(left);
  const rightKeys = Object.keys(right);
  if (leftKeys.length !== rightKeys.length) return false;
  for (const key of leftKeys) {
    if (!Object.prototype.hasOwnProperty.call(right, key) || !deepEqual(left[key], right[key])) return false;
  }
  return true;
}

function cloneValue(value) {
  if (Array.isArray(value)) return value.map(cloneValue);
  if (isObject(value)) {
    const copy = Object.create(null);
    for (const key of Object.keys(value)) copy[key] = cloneValue(value[key]);
    return copy;
  }
  return value;
}

function displayPath(prefix, key) {
  return prefix ? `${prefix}.${key}` : key;
}

function scalarKey(yaml, node) {
  if (yaml.isScalar(node)) {
    if (typeof node.value === 'string' || typeof node.value === 'number' || typeof node.value === 'boolean') {
      return String(node.value);
    }
  }
  throw new Error('settings YAML contains a non-scalar map key');
}

function mergeDuplicateValues(left, right, valuePath, state) {
  if (left === null && isObject(right)) return right;
  if (right === null && isObject(left)) return left;
  if (isObject(left) && isObject(right)) return mergeDuplicateMaps(left, right, valuePath, state);
  if (deepEqual(left, right)) return left;
  // A known previous AgentPort preset writer could emit the same setting map
  // twice. Keep the first value, but the caller creates a backup before any
  // normalisation, so the user can recover the original if required.
  if (valuePath === 'agent-presets.default') return left;
  throw new Error(`ambiguous duplicate YAML value at ${valuePath}`);
}

function mergeDuplicateMaps(left, right, mapPath, state) {
  const merged = left;
  for (const key of Object.keys(right)) {
    const valuePath = displayPath(mapPath, key);
    if (Object.prototype.hasOwnProperty.call(merged, key)) {
      merged[key] = mergeDuplicateValues(merged[key], right[key], valuePath, state);
    } else {
      merged[key] = right[key];
    }
  }
  return merged;
}

function nodeToValue(yaml, node, valuePath, state) {
  if (node === null || node === undefined) return null;
  if (yaml.isScalar(node)) return node.value;
  if (yaml.isMap(node)) {
    const result = Object.create(null);
    for (const pair of node.items) {
      const key = scalarKey(yaml, pair.key);
      const childPath = displayPath(valuePath, key);
      const value = nodeToValue(yaml, pair.value, childPath, state);
      if (Object.prototype.hasOwnProperty.call(result, key)) {
        state.duplicates += 1;
        result[key] = mergeDuplicateValues(result[key], value, childPath, state);
      } else {
        result[key] = value;
      }
    }
    return result;
  }
  if (yaml.isSeq(node)) return node.items.map((item, index) => nodeToValue(yaml, item, `${valuePath}[${index}]`, state));
  if (yaml.isAlias(node)) throw new Error(`settings YAML aliases are not supported at ${valuePath || 'root'}`);
  throw new Error(`settings YAML contains an unsupported node at ${valuePath || 'root'}`);
}

function ensureMap(parent, key, valuePath) {
  if (!Object.prototype.hasOwnProperty.call(parent, key) || parent[key] === null) {
    parent[key] = Object.create(null);
    return parent[key];
  }
  if (!isObject(parent[key])) throw new Error(`settings YAML value at ${valuePath} must be a map`);
  return parent[key];
}

function overlayValue(existing, desired, valuePath) {
  if (isObject(desired)) {
    if (existing === undefined) return cloneValue(desired);
    if (!isObject(existing)) throw new Error(`cannot replace scalar settings value at ${valuePath}`);
    const result = existing;
    for (const key of Object.keys(desired)) {
      const childPath = displayPath(valuePath, key);
      if (key === 'models' && Array.isArray(desired[key])) {
        result[key] = mergeModels(Array.isArray(result[key]) ? result[key] : [], desired[key], childPath);
      } else if (Object.prototype.hasOwnProperty.call(result, key) && isObject(result[key]) && isObject(desired[key])) {
        result[key] = overlayValue(result[key], desired[key], childPath);
      } else {
        result[key] = cloneValue(desired[key]);
      }
    }
    return result;
  }
  return cloneValue(desired);
}

function mergeModels(existing, desired, valuePath) {
  const result = existing.map(cloneValue);
  for (const desiredModel of desired) {
    if (!isObject(desiredModel) || typeof desiredModel.id !== 'string') {
      throw new Error(`settings models at ${valuePath} must contain map entries with string ids`);
    }
    const index = result.findIndex(model => isObject(model) && model.id === desiredModel.id);
    if (index < 0) result.push(cloneValue(desiredModel));
    else result[index] = overlayValue(result[index], desiredModel, `${valuePath}[${desiredModel.id}]`);
  }
  return result;
}

function normaliseOperations(raw) {
  if (raw === null || raw === undefined) return [];
  if (Array.isArray(raw)) return raw;
  return [raw];
}

function applyOperations(root, operations) {
  for (const operation of normaliseOperations(operations)) {
    if (!operation || typeof operation.kind !== 'string') throw new Error('settings operation is missing its kind');
    switch (operation.kind) {
      case 'repair':
        break;
      case 'ensure-provider': {
        const llm = ensureMap(root, 'llm-pi-ai', 'llm-pi-ai');
        const providers = ensureMap(llm, 'providers', 'llm-pi-ai.providers');
        if (typeof operation.provider !== 'string' || !isObject(operation.value)) throw new Error('ensure-provider operation is invalid');
        providers[operation.provider] = overlayValue(providers[operation.provider], operation.value, `llm-pi-ai.providers.${operation.provider}`);
        break;
      }
      case 'remove-empty-provider': {
        if (!isObject(root['llm-pi-ai'])) break;
        const providers = root['llm-pi-ai'].providers;
        if (!isObject(providers) || typeof operation.provider !== 'string') break;
        const value = providers[operation.provider];
        if (isObject(value) && (!Array.isArray(value.models) || value.models.length === 0)) delete providers[operation.provider];
        break;
      }
      case 'set-default-model': {
        if (typeof operation.provider !== 'string' || typeof operation.model !== 'string') throw new Error('set-default-model operation is invalid');
        const desired = { provider: operation.provider, model: operation.model };
        if (Object.prototype.hasOwnProperty.call(root, 'agent-default-model')) {
          root['agent-default-model'] = overlayValue(root['agent-default-model'], desired, 'agent-default-model');
        } else {
          root['agent-default-model'] = desired;
        }
        break;
      }
      case 'set-preset-default': {
        if (typeof operation.preset !== 'string') throw new Error('set-preset-default operation is invalid');
        const presets = ensureMap(root, 'agent-presets', 'agent-presets');
        presets.default = operation.preset;
        break;
      }
      default:
        throw new Error(`unknown settings operation ${operation.kind}`);
    }
  }
}

function parseRoot(yaml, source) {
  const document = yaml.parseDocument(source || '', { uniqueKeys: false, prettyErrors: false });
  if (document.errors && document.errors.length > 0) throw new Error('settings YAML is invalid');
  if (document.warnings && document.warnings.length > 0) throw new Error('settings YAML contains unsupported warnings');
  if (!document.contents) return { root: Object.create(null), duplicateCount: 0 };
  const state = { duplicates: 0 };
  const root = nodeToValue(yaml, document.contents, '', state);
  if (!isObject(root)) throw new Error('settings YAML root must be a map');
  return { root, duplicateCount: state.duplicates };
}

function validateOutput(yaml, source) {
  const document = yaml.parseDocument(source, { uniqueKeys: true, prettyErrors: false });
  if (document.errors && document.errors.length > 0) throw new Error('generated settings YAML failed validation');
  if (document.warnings && document.warnings.length > 0) throw new Error('generated settings YAML contains warnings');
  if (!document.contents || !yaml.isMap(document.contents)) throw new Error('generated settings YAML root must be a map');
}

function atomicReplace(filePath, contents, backupPath, existed, originalContents) {
  const directory = path.dirname(filePath);
  fs.mkdirSync(directory, { recursive: true });
  const suffix = crypto.randomBytes(12).toString('hex');
  const tempPath = `${filePath}.agentport-${suffix}.tmp`;
  try {
    fs.writeFileSync(tempPath, contents, { encoding: 'utf8', flag: 'wx' });
    if (existed) {
      const currentContents = fs.readFileSync(filePath, 'utf8');
      if (currentContents !== originalContents) throw new Error('settings changed during update');
      if (backupPath && !fs.existsSync(backupPath)) fs.copyFileSync(filePath, backupPath);
    }
    // Node's Windows rename uses MoveFileEx with replacement semantics. The
    // destination remains intact if the operation fails because Harness has
    // the file open, so there is no remove-then-create gap.
    fs.renameSync(tempPath, filePath);
  } catch (error) {
    try { if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath); } catch (_) {}
    throw new Error('settings YAML atomic replacement failed');
  }
}

function run(argv) {
  if (argv.length !== 5 || argv[0] !== '--apply') throw new Error('settings helper arguments are invalid');
  const settingsPath = path.resolve(argv[1]);
  const operationsPath = path.resolve(argv[2]);
  const backupPath = argv[3] ? path.resolve(argv[3]) : '';
  const yamlRoot = path.resolve(argv[4]);
  const yaml = require(yamlRoot);
  const original = fs.existsSync(settingsPath) ? fs.readFileSync(settingsPath, 'utf8') : '';
  const operations = JSON.parse(fs.readFileSync(operationsPath, 'utf8'));
  const parsed = parseRoot(yaml, original);
  const root = parsed.root;
  const before = cloneValue(root);
  applyOperations(root, operations);
  let candidate = yaml.stringify(root, { indent: 2, lineWidth: 0 });
  if (!candidate.endsWith('\n')) candidate += '\n';
  validateOutput(yaml, candidate);
  if (parsed.duplicateCount === 0 && deepEqual(before, root)) {
    process.stdout.write('unchanged\n');
    return;
  }
  atomicReplace(settingsPath, candidate, backupPath, fs.existsSync(settingsPath), original);
  process.stdout.write('changed\n');
}

try {
  run(process.argv.slice(2));
} catch (error) {
  fail(error && error.message ? error.message : 'settings YAML operation failed');
}
