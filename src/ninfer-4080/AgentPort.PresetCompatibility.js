'use strict';
// Migrate the persona schema in AgentPort-owned presets without changing their
// instructions, tools, or the user's other presets. Keep the original on disk.
const fs = require('fs');
const crypto = require('crypto');
try {
  const file = process.argv[2];
  const yaml = require(process.argv[3]);
  const original = fs.readFileSync(file, 'utf8');
  const doc = yaml.parseDocument(original);
  if (doc.errors.length || !yaml.isSeq(doc.contents)) throw Error('Invalid preset');
  let changed = false;
  yaml.visit(doc, { Map(_, map) {
    if (map.get('name') !== '@deepseek-ai/dsh-persona') return;
    const config = map.get('config');
    if (!yaml.isMap(config) || config.has('prefix')) return;
    const text = config.get('text');
    if (typeof text !== 'string') throw Error('Missing persona instructions');
    config.set('prefix', text);
    config.delete('text');
    changed = true;
  }});
  if (changed) {
    const output = doc.toString();
    if (yaml.parseDocument(output).errors.length) throw Error('Invalid migrated preset');
    const suffix = crypto.randomBytes(8).toString('hex');
    const temp = file + '.' + suffix + '.tmp';
    try {
      fs.writeFileSync(temp, output, { flag: 'wx' });
      if (fs.readFileSync(file, 'utf8') !== original) throw Error('Preset changed during repair');
      fs.copyFileSync(file, file + '.before-prefix-' + suffix, fs.constants.COPYFILE_EXCL);
      fs.renameSync(temp, file);
    } finally { if (fs.existsSync(temp)) fs.unlinkSync(temp); }
  }
  console.log(changed ? 'changed' : 'unchanged');
} catch (_) {
  console.error('Preset compatibility repair failed; original instructions were not replaced.');
  process.exitCode = 1;
}
