const EXT = globalThis.browser || globalThis.chrome;
const BRIDGE = 'http://127.0.0.1:17321';
const $ = id => document.getElementById(id);
const send = $('send'), msg = $('message'), dot = $('dot'), bridgeStatus = $('bridgeStatus'), companionHelp=$('companionHelp');
let bridgeOK = false;

function setMessage(text, kind) {
  msg.textContent = text || '';
  msg.className = 'message' + (kind ? ' ' + kind : '');
}
function setProgress(p, label, detail) {
  $('progressWrap').hidden = false;
  $('bar').style.width = Math.max(0, Math.min(100, p)) + '%';
  $('progressPct').textContent = Math.round(p) + '%';
  $('progressLabel').textContent = label || '';
  $('detail').textContent = detail || '';
}
async function checkBridge() {
  try {
    const r = await fetch(BRIDGE + '/health', { cache: 'no-store' });
    if (!r.ok) throw new Error('offline');
    const j = await r.json();
    bridgeOK = !!j.ok && !j.busy;
    if(companionHelp) companionHelp.hidden = !!j.ok;
    bridgeStatus.textContent = j.busy ? 'After Effects is building…' : (j.ok ? 'After Effects connected' : 'AE bridge unavailable');
    dot.className = 'dot ' + (j.ok ? 'ok' : 'bad');
    send.disabled = !bridgeOK;
  } catch (_) {
    bridgeOK = false;
    if(companionHelp) companionHelp.hidden = false;
    bridgeStatus.textContent = 'Open Web2AE in After Effects';
    dot.className = 'dot bad';
    send.disabled = true;
  }
}
async function loadTab() {
  const tabs = await EXT.tabs.query({ active: true, currentWindow: true });
  const tab = tabs && tabs[0];
  if (!tab) return;
  $('pageTitle').textContent = tab.title || 'Current tab';
  $('pageUrl').textContent = tab.url || '';
}
EXT.runtime.onMessage.addListener(message => {
  if (message && message.type === 'capture-progress') {
    setProgress(message.percent || 0, message.label || 'Working…', message.detail || '');
  }
});
async function requestHighFidelityPermission(){
  try{
    const manifest=EXT.runtime.getManifest();
    const optional=manifest.optional_permissions||[];
    if(optional.indexOf('debugger')<0 || !EXT.permissions) return true;
    const has=await EXT.permissions.contains({permissions:['debugger']});
    if(has) return true;
    return await EXT.permissions.request({permissions:['debugger']});
  }catch(_){return false;}
}
$('openSetup').addEventListener('click',()=>EXT.tabs.create({url:EXT.runtime.getURL('setup.html')}));
send.addEventListener('click', async () => {
  if (!bridgeOK) return;
  await requestHighFidelityPermission();
  send.disabled = true;
  setMessage('');
  setProgress(3, 'Starting capture…', 'Reading the live DOM and computed CSS.');
  try {
    const res = await EXT.runtime.sendMessage({ type: 'capture-and-send' });
    if (!res || !res.ok) throw new Error(res && res.error ? res.error : 'Capture failed.');
    setProgress(100, 'Sent to After Effects', `${res.layers} visual layers · ${res.groups} groups · ${(res.diagnostics&&res.diagnostics.engine)||'DOM'} capture`);
    const auto = !!(res.response && res.response.autoBuild);
    setMessage(auto ? 'Capture sent. After Effects is building the comp.' : 'Capture received in After Effects. Click Build Latest Capture when ready.', 'ok');
  } catch (error) {
    setMessage(error && error.message ? error.message : String(error), 'error');
    setProgress(0, 'Capture failed', 'Check the AE panel Activity log for details.');
  } finally {
    send.disabled = !bridgeOK;
  }
});
Promise.all([checkBridge(), loadTab()]);
setInterval(checkBridge, 2500);
