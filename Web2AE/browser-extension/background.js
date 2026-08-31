const EXT = globalThis.browser || globalThis.chrome;
const IS_FIREFOX = typeof globalThis.browser !== 'undefined' && !!globalThis.browser.runtime;
const BRIDGE = 'http://127.0.0.1:17321';
const CDP_STYLES = [
  'display','visibility','content-visibility','opacity','font-family','font-size','font-weight','font-style','color','line-height','letter-spacing','text-align','text-transform','white-space',
  'background-color','background-image','border-top-width','border-right-width','border-bottom-width','border-left-width','border-top-color','border-right-color','border-bottom-color','border-left-color',
  'border-top-left-radius','border-top-right-radius','border-bottom-right-radius','border-bottom-left-radius','box-shadow','filter','backdrop-filter','clip-path','mask-image','mix-blend-mode','overflow-x','overflow-y','object-fit','position','z-index','transform'
];

function progress(percent, label, detail) {
  try {
    const p = EXT.runtime.sendMessage({ type: 'capture-progress', percent, label, detail });
    if (p && typeof p.catch === 'function') p.catch(() => {});
  } catch (_) {}
}
function clean(s){return String(s||'').replace(/\s+/g,' ').trim();}
function px(v){const n=parseFloat(v);return Number.isFinite(n)?n:0;}
function alpha(c){const s=String(c||'').trim();if(!s||s==='transparent')return 0;const m=s.match(/rgba?\(([^)]+)\)/i);if(!m)return 1;const p=m[1].split(',').map(Number);return p.length>3&&!Number.isNaN(p[3])?p[3]:1;}
function norm(c){return String(c||'').replace(/\s+/g,'').toLowerCase();}
function clamp(v,a,b){return Math.max(a,Math.min(b,v));}
function rectInViewport(b,scrollX,scrollY,W,H){
  if(!b||b.length<4)return null;let x=Number(b[0])-scrollX,y=Number(b[1])-scrollY,w=Number(b[2]),h=Number(b[3]);
  if(!Number.isFinite(x+y+w+h)||w<=.5||h<=.5||x>=W||y>=H||x+w<=0||y+h<=0)return null;
  const l=clamp(x,0,W),t=clamp(y,0,H),r=clamp(x+w,0,W),bb=clamp(y+h,0,H);
  if(r-l<=.5||bb-t<=.5)return null;return{x:+l.toFixed(2),y:+t.toFixed(2),w:+(r-l).toFixed(2),h:+(bb-t).toFixed(2)};
}
function rareMap(d){const m=new Map();if(d&&d.index&&d.value)for(let i=0;i<d.index.length;i++)m.set(d.index[i],d.value[i]);return m;}
function parseAttrs(raw,strings){const o={};if(!raw)return o;for(let i=0;i+1<raw.length;i+=2)o[String(strings[raw[i]]||'').toLowerCase()]=String(strings[raw[i+1]]||'');return o;}
function debuggerAttach(target){return new Promise((resolve,reject)=>{try{chrome.debugger.attach(target,'1.3',()=>{const e=chrome.runtime.lastError;if(e)reject(new Error(e.message));else resolve();});}catch(e){reject(e);}});}
function debuggerDetach(target){return new Promise(resolve=>{try{chrome.debugger.detach(target,()=>resolve());}catch(_e){resolve();}});}
function debuggerCommand(target,method,params){return new Promise((resolve,reject)=>{try{chrome.debugger.sendCommand(target,method,params||{},result=>{const e=chrome.runtime.lastError;if(e)reject(new Error(e.message));else resolve(result);});}catch(e){reject(e);}});}

function sceneFromCDP(snapshot,metrics,tab){
  const strings=snapshot.strings||[], docs=snapshot.documents||[];
  const vv=metrics&&metrics.visualViewport||metrics&&metrics.layoutViewport||{};
  const W=Math.max(1,Math.round(vv.clientWidth||vv.width||0)),H=Math.max(1,Math.round(vv.clientHeight||vv.height||0));
  const fallbackW=W||1280,fallbackH=H||720; const viewW=fallbackW,viewH=fallbackH;
  const layers=[],groups=[],seen=new Set(),groupIds=new Map();let lid=0,gid=0;
  const diagnostics={engine:'cdp-dom-snapshot',documents:docs.length,nodes:0,layoutNodes:0,visible:0,media:0,text:0,boxes:0,svg:0,groups:0,errors:0,fallback:false,errorSamples:[]};
  function add(layer){if(layers.length>=5000)return;const r=layer.rect||{},k=[layer.kind,Math.round(r.x*2),Math.round(r.y*2),Math.round(r.w*2),Math.round(r.h*2),layer.text||layer.name||''].join('|');if(seen.has(k))return;seen.add(k);layer.id='l'+(++lid);layers.push(layer);}
  function isGroupTag(tag,role,r){const t=tag.toLowerCase(),ro=(role||'').toLowerCase(),area=(r.w*r.h)/(viewW*viewH);if(['header','nav','main','footer','aside','section','article','li'].includes(t))return true;if(['navigation','banner','main','contentinfo','complementary','region','toolbar','listitem'].includes(ro))return true;if(area>.004&&area<.45&&(/renderer|card|tile|grid-media|rich-item|item-renderer|compact-video|video-renderer/.test(t)))return true;return false;}
  function groupName(tag,attrs){return clean(attrs['aria-label']||attrs.title||attrs.id||tag).slice(0,80)||'Group';}
  for(let di=0;di<docs.length;di++){
    const doc=docs[di],nodes=doc.nodes||{},layout=doc.layout||{},nodeCount=(nodes.nodeType||[]).length;diagnostics.nodes+=nodeCount;diagnostics.layoutNodes+=(layout.nodeIndex||[]).length;
    const scrollX=Number(doc.scrollOffsetX||0),scrollY=Number(doc.scrollOffsetY||0);
    const parent=nodes.parentIndex||[], types=nodes.nodeType||[], names=nodes.nodeName||[], values=nodes.nodeValue||[], attrsArr=nodes.attributes||[], currentSrc=rareMap(nodes.currentSourceURL), inputVal=rareMap(nodes.inputValue), textVal=rareMap(nodes.textValue);
    const textBearing=new Set(), elementChildCount=new Map();
    for(let ni=0;ni<nodeCount;ni++){const pi=parent[ni];if(pi!=null&&pi>=0&&types[ni]===1)elementChildCount.set(pi,(elementChildCount.get(pi)||0)+1);}
    for(let ni=0;ni<nodeCount;ni++){if(types[ni]!==3)continue;const txt=clean(strings[values[ni]]||'');if(!txt)continue;let p=parent[ni],guard=0;while(p!=null&&p>=0&&guard++<120){textBearing.add(p);p=parent[p];}}
    const layoutForNode=new Map();for(let i=0;i<(layout.nodeIndex||[]).length;i++)layoutForNode.set(layout.nodeIndex[i],i);
    function styleForLayout(li){const out={};const arr=layout.styles&&layout.styles[li]||[];for(let i=0;i<CDP_STYLES.length;i++)out[CDP_STYLES[i]]=String(strings[arr[i]]||'');return out;}
    function styleForNode(ni){const li=layoutForNode.get(ni);return li==null?null:styleForLayout(li);}
    function rectForNode(ni){const li=layoutForNode.get(ni);if(li==null)return null;return rectInViewport(layout.bounds&&layout.bounds[li],scrollX,scrollY,viewW,viewH);}
    function attrsFor(ni){return parseAttrs(attrsArr[ni],strings);}
    function clipForNode(ni,baseRect){
      let r={x:baseRect.x,y:baseRect.y,w:baseRect.w,h:baseRect.h},rad=[0,0,0,0],p=ni,guard=0;
      const own=styleForNode(ni);if(own)rad=[px(own['border-top-left-radius']),px(own['border-top-right-radius']),px(own['border-bottom-right-radius']),px(own['border-bottom-left-radius'])];
      while(p!=null&&p>=0&&guard++<120){
        const st=styleForNode(p),pr=rectForNode(p);
        if(st&&pr){const ox=st['overflow-x']||'visible',oy=st['overflow-y']||'visible',cx=['hidden','clip','scroll','auto'].includes(ox),cy=['hidden','clip','scroll','auto'].includes(oy);
          if(cx||cy){const l=cx?Math.max(r.x,pr.x):r.x,t=cy?Math.max(r.y,pr.y):r.y,rr=cx?Math.min(r.x+r.w,pr.x+pr.w):r.x+r.w,bb=cy?Math.min(r.y+r.h,pr.y+pr.h):r.y+r.h;r={x:l,y:t,w:Math.max(0,rr-l),h:Math.max(0,bb-t)};const ar=[px(st['border-top-left-radius']),px(st['border-top-right-radius']),px(st['border-bottom-right-radius']),px(st['border-bottom-left-radius'])];if(ar.some(v=>v>.1))rad=ar;}
        }
        p=parent[p];
      }
      return{rect:r,radii:rad};
    }
    function nearestGroup(ni){let p=ni,guard=0;while(p!=null&&p>=0&&guard++<120){const li=layoutForNode.get(p);if(li!=null){const r=rectForNode(p);if(r){const tag=String(strings[names[p]]||'').toLowerCase(),a=attrsFor(p),role=a.role||'';if(isGroupTag(tag,role,r)){const key=di+':'+p;if(!groupIds.has(key)){const id='g'+(++gid);groupIds.set(key,id);groups.push({id,name:groupName(tag,a),tag,role,rect:r});}return groupIds.get(key);}}}p=parent[p];}return null;}
    for(let li=0;li<(layout.nodeIndex||[]).length;li++){
      const ni=layout.nodeIndex[li],type=types[ni],tag=String(strings[names[ni]]||'').toUpperCase(),st=styleForLayout(li),baseRect=rectInViewport(layout.bounds&&layout.bounds[li],scrollX,scrollY,viewW,viewH);
      if(!baseRect)continue;if(st.display==='none'||st.visibility==='hidden'||st['content-visibility']==='hidden'||parseFloat(st.opacity||'1')===0)continue;const clipped=clipForNode(ni,baseRect),r=clipped.rect;if(!r||r.w<=.5||r.h<=.5)continue;diagnostics.visible++;
      const paint=(layout.paintOrders&&layout.paintOrders[li]!=null)?Number(layout.paintOrders[li]):li;const groupId=nearestGroup(ni);const a=attrsFor(ni);
      if(type===3){const txt=clean(strings[(layout.text||[])[li]]||strings[values[ni]]||'');if(!txt)continue;add({kind:'text',name:txt.slice(0,72),groupId,rect:r,text:txt,opacity:parseFloat(st.opacity||'1')||1,style:{fontFamily:(st['font-family']||'Arial').split(',')[0].replace(/["']/g,'').trim(),fontSize:px(st['font-size'])||16,fontWeight:parseInt(st['font-weight'],10)||400,fontStyle:st['font-style']||'normal',color:st.color||'rgb(0,0,0)',lineHeight:px(st['line-height'])||0,letterSpacing:px(st['letter-spacing'])||0,textAlign:st['text-align']||'left',textTransform:st['text-transform']||'none',whiteSpace:st['white-space']||'normal'},order:paint*10+8});diagnostics.text++;continue;}
      if(type!==1)continue;
      const radii=clipped.radii;
      const name=clean(a['aria-label']||a.alt||a.title||a.id||tag.toLowerCase()).slice(0,72)||tag.toLowerCase();
      const media=['IMG','VIDEO','CANVAS','IFRAME','OBJECT','EMBED','SVG','PICTURE'].includes(tag);
      const complex=(st['background-image']&&st['background-image']!=='none')||(st.filter&&st.filter!=='none')||(st['backdrop-filter']&&st['backdrop-filter']!=='none')||(st['clip-path']&&st['clip-path']!=='none')||(st['mask-image']&&st['mask-image']!=='none')||(st['mix-blend-mode']&&st['mix-blend-mode']!=='normal');
      const hasTextDesc=textBearing.has(ni), hasElementChildren=(elementChildCount.get(ni)||0)>0;
      if(media){add({kind:'raster',name,groupId,rect:r,radii,opacity:parseFloat(st.opacity||'1')||1,reason:tag==='SVG'?'SVG/icon artwork':'Media element',sourceKind:tag.toLowerCase(),assetUrl:currentSrc.has(ni)?String(strings[currentSrc.get(ni)]||''):(a.src||null),order:paint*10+6});diagnostics.media++;if(tag==='SVG')diagnostics.svg++;continue;}
      if(['INPUT','TEXTAREA','SELECT'].includes(tag)){add({kind:'raster',name,groupId,rect:r,radii,opacity:parseFloat(st.opacity||'1')||1,reason:'Native form control',sourceKind:tag.toLowerCase(),order:paint*10+6});diagnostics.media++;continue;}
      if(complex&&!hasTextDesc&&!hasElementChildren){add({kind:'raster',name,groupId,rect:r,radii,opacity:parseFloat(st.opacity||'1')||1,reason:'Complex CSS element',sourceKind:tag.toLowerCase(),order:paint*10+6});diagnostics.media++;continue;}
      const bw=[px(st['border-top-width']),px(st['border-right-width']),px(st['border-bottom-width']),px(st['border-left-width'])],hasBorder=bw.some(v=>v>.01),hasBg=alpha(st['background-color'])>.01;
      if(!hasBorder&&!hasBg)continue;
      const area=(r.w*r.h)/(viewW*viewH);if(area>.82&&!['BUTTON'].includes(tag))continue;
      let parentBg='';const pi=parent[ni],pli=layoutForNode.get(pi);if(pli!=null)parentBg=styleForLayout(pli)['background-color']||'';
      if(hasBg&&!hasBorder&&norm(st['background-color'])===norm(parentBg)&&!['BUTTON'].includes(tag)&&!(a.role==='button'))continue;
      add({kind:'box',name,groupId,rect:r,opacity:parseFloat(st.opacity||'1')||1,style:{backgroundColor:st['background-color']||'transparent',border:{top:{w:bw[0],c:st['border-top-color']},right:{w:bw[1],c:st['border-right-color']},bottom:{w:bw[2],c:st['border-bottom-color']},left:{w:bw[3],c:st['border-left-color']}},radii,boxShadow:st['box-shadow']||'none'},order:paint*10+1});diagnostics.boxes++;
    }
  }
  diagnostics.groups=groups.length;diagnostics.fallback=layers.length<2;
  let background='rgb(255,255,255)';const bgCandidate=layers.filter(l=>l.kind==='box'&&l.rect.w>viewW*.9&&l.rect.h>viewH*.9).sort((a,b)=>a.order-b.order)[0];if(bgCandidate&&bgCandidate.style)background=bgCandidate.style.backgroundColor||background;
  return {version:4,source:{url:tab.url||'',title:tab.title||'',capturedAt:new Date().toISOString()},viewport:{width:viewW,height:viewH,captureWidth:viewW,captureHeight:viewH,dpr:1,scrollX:0,scrollY:0},background,groups,layers,diagnostics};
}

async function captureViaCDP(tab){
  if(IS_FIREFOX) throw new Error('CDP capture is Chromium-only.');
  if(!(globalThis.chrome&&chrome.debugger))throw new Error('Chrome DevTools capture API unavailable.');
  const target={tabId:tab.id};let attached=false;
  try{
    progress(10,'Reading Chrome render tree…','Using the browser’s DOMSnapshot layout engine for exact element geometry.');
    await debuggerAttach(target);attached=true;
    const [metrics,snapshot]=await Promise.all([
      debuggerCommand(target,'Page.getLayoutMetrics',{}),
      debuggerCommand(target,'DOMSnapshot.captureSnapshot',{computedStyles:CDP_STYLES,includePaintOrder:true,includeDOMRects:true,includeBlendedBackgroundColors:false,includeTextColorOpacities:false})
    ]);
    const scene=sceneFromCDP(snapshot,metrics,tab);
    return scene;
  } finally {if(attached)await debuggerDetach(target);}
}

async function captureViaInjected(tab){
  progress(10,'Reading live page…','Compatibility capture: walking the live DOM and computed CSS.');
  await EXT.scripting.executeScript({target:{tabId:tab.id},files:['capture_page.js']});
  const results=await EXT.scripting.executeScript({target:{tabId:tab.id},func:()=>window.__web2aeCapturePage()});
  const scene=results&&results[0]&&results[0].result;if(!scene)throw new Error('Could not read the page DOM.');return scene;
}
async function postCapture(payload){
  const r=await fetch(BRIDGE+'/capture',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  if(!r.ok){let t='';try{t=await r.text();}catch(_){}throw new Error(`After Effects bridge returned ${r.status}${t?': '+t:''}`);}return r.json();
}
async function captureActive(){
  const tabs=await EXT.tabs.query({active:true,currentWindow:true});const tab=tabs&&tabs[0];if(!tab||!tab.id)throw new Error('No active browser tab.');if(!/^https?:|^file:/.test(tab.url||''))throw new Error('Open a normal website first.');
  let scene=null,primaryError=null;
  try{scene=await captureViaCDP(tab);}catch(e){primaryError=e;progress(18,'Chrome render-tree capture unavailable','Falling back to the compatibility DOM collector.');}
  if(!scene||!scene.layers||scene.layers.length<2){
    try{const fallback=await captureViaInjected(tab);if(!scene||((fallback.layers||[]).length>(scene.layers||[]).length))scene=fallback;}catch(e){if(!primaryError)primaryError=e;}
  }
  if(!scene)throw primaryError||new Error('Page capture failed.');
  if((scene.layers||[]).length<2)throw new Error(`Web2AE could not find rendered page elements. Capture diagnostics: ${JSON.stringify(scene.diagnostics||{})}`);
  progress(50,'Capturing exact browser pixels…',`${scene.layers.length} element layers identified. Capturing the visual reference for raster-only elements.`);
  const screenshotDataUrl=await EXT.tabs.captureVisibleTab(tab.windowId,{format:'png'});
  progress(74,'Sending element scene to After Effects…',`${scene.layers.length} visual layers · ${scene.groups.length} semantic groups · ${scene.diagnostics&&scene.diagnostics.engine||'DOM'} engine`);
  const response=await postCapture({scene,screenshotDataUrl,browser:{tabId:tab.id,url:tab.url,title:tab.title}});
  progress(100,'Sent to After Effects','The AE panel has received the element-level capture.');
  return{ok:true,layers:scene.layers.length,groups:scene.groups.length,diagnostics:scene.diagnostics||null,response};
}
EXT.runtime.onMessage.addListener((message,_sender,sendResponse)=>{if(!message||message.type!=='capture-and-send')return false;captureActive().then(sendResponse).catch(error=>sendResponse({ok:false,error:error&&error.message?error.message:String(error)}));return true;});
