(function(){
  const CAPTURE_VERSION='1.0.0';
  if(window.__web2aeCapturePage && window.__web2aeCaptureVersion===CAPTURE_VERSION)return;
  window.__web2aeCaptureVersion=CAPTURE_VERSION;

  const MAX_LAYERS=4500, MAX_ELEMENTS=30000;
  const SKIP=new Set(['SCRIPT','STYLE','LINK','META','NOSCRIPT','HEAD','TITLE','BR','SOURCE','TRACK','TEMPLATE']);
  const MEDIA=new Set(['IMG','VIDEO','CANVAS','IFRAME','OBJECT','EMBED']);
  const CONTROL=new Set(['BUTTON','INPUT','TEXTAREA','SELECT']);
  function clamp(v,a,b){return Math.max(a,Math.min(b,v));}
  function vw(){return document.documentElement.clientWidth||window.innerWidth||1;}
  function vh(){return document.documentElement.clientHeight||window.innerHeight||1;}
  function safeStyle(el,pseudo){try{return getComputedStyle(el,pseudo||null);}catch(_e){return null;}}
  function safeRect(el){try{return el.getBoundingClientRect();}catch(_e){return null;}}
  function parentEl(el){if(!el)return null;if(el.parentElement)return el.parentElement;try{const r=el.getRootNode&&el.getRootNode();return r&&r.host?r.host:null;}catch(_e){return null;}}
  function visibleRect(r){return !!r&&r.width>.5&&r.height>.5&&r.right>0&&r.bottom>0&&r.left<vw()&&r.top<vh();}
  function px(v){const n=parseFloat(v);return Number.isFinite(n)?n:0;}
  function alpha(c){const s=String(c||'').trim();if(!s||s==='transparent')return 0;const m=s.match(/rgba?\(([^)]+)\)/i);if(!m)return 1;const p=m[1].split(',').map(Number);return p.length>3&&!Number.isNaN(p[3])?p[3]:1;}
  function clean(s){return String(s||'').replace(/\s+/g,' ').trim();}
  function ownText(el){let s='';try{for(const n of Array.from(el.childNodes||[]))if(n.nodeType===3)s+=' '+n.nodeValue;}catch(_e){}return clean(s);}
  function rectOut(r){const l=clamp(r.left,0,vw()),t=clamp(r.top,0,vh()),rr=clamp(r.right,0,vw()),bb=clamp(r.bottom,0,vh());return{x:+l.toFixed(2),y:+t.toFixed(2),w:+Math.max(0,rr-l).toFixed(2),h:+Math.max(0,bb-t).toFixed(2)};}
  function colorNorm(c){return String(c||'').replace(/\s+/g,'').toLowerCase();}
  function radii(st){return [px(st.borderTopLeftRadius),px(st.borderTopRightRadius),px(st.borderBottomRightRadius),px(st.borderBottomLeftRadius)];}
  function border(st){return{top:{w:px(st.borderTopWidth),c:st.borderTopColor},right:{w:px(st.borderRightWidth),c:st.borderRightColor},bottom:{w:px(st.borderBottomWidth),c:st.borderBottomColor},left:{w:px(st.borderLeftWidth),c:st.borderLeftColor}};}
  function clipInfo(el,r){
    let left=r.left,top=r.top,right=r.right,bottom=r.bottom,rad=radii(safeStyle(el)||{}),p=parentEl(el),guard=0;
    while(p&&p!==document.documentElement&&guard++<90){
      const s=safeStyle(p),pr=safeRect(p);if(s&&pr){const ox=s.overflowX||s.overflow||'visible',oy=s.overflowY||s.overflow||'visible';const cx=['hidden','clip','scroll','auto'].includes(ox),cy=['hidden','clip','scroll','auto'].includes(oy);if(cx){left=Math.max(left,pr.left);right=Math.min(right,pr.right);}if(cy){top=Math.max(top,pr.top);bottom=Math.min(bottom,pr.bottom);}if(cx||cy){const ar=radii(s);if(ar.some(v=>v>.1))rad=ar;}}
      p=parentEl(p);
    }
    return{rect:{left,top,right,bottom,width:Math.max(0,right-left),height:Math.max(0,bottom-top)},radii:rad};
  }
  function effOpacity(el){let o=1,p=el,g=0;while(p&&p.nodeType===1&&g++<90){const s=safeStyle(p);if(s){const n=parseFloat(s.opacity);if(Number.isFinite(n))o*=n;}p=parentEl(p);}return +clamp(o,0,1).toFixed(3);}
  function label(el){const aria=clean(el.getAttribute&&el.getAttribute('aria-label'));const alt=clean(el.getAttribute&&el.getAttribute('alt'));const t=ownText(el).slice(0,50);const tag=(el.tagName||'element').toLowerCase();return (aria||alt||t||tag).slice(0,72);}
  function fontStyle(st){return{fontFamily:(st.fontFamily||'Arial').split(',')[0].replace(/["']/g,'').trim(),fontSize:px(st.fontSize)||16,fontWeight:parseInt(st.fontWeight,10)||400,fontStyle:st.fontStyle||'normal',color:st.color||'rgb(0,0,0)',lineHeight:px(st.lineHeight)||0,letterSpacing:px(st.letterSpacing)||0,textAlign:st.textAlign||'left',textTransform:st.textTransform||'none',whiteSpace:st.whiteSpace||'normal'};}
  function isVisible(el){const s=safeStyle(el),r=safeRect(el);return !!s&&visibleRect(r)&&s.display!=='none'&&s.visibility!=='hidden'&&s.contentVisibility!=='hidden'&&parseFloat(s.opacity||1)!==0;}
  function isInteractive(el){const role=(el.getAttribute&&el.getAttribute('role')||'').toLowerCase();return CONTROL.has(el.tagName)||['button','link','tab','menuitem','checkbox','radio','switch','textbox','combobox'].includes(role)||el.tagName==='A';}
  function groupCandidate(el){
    const tag=(el.tagName||'').toLowerCase(),role=(el.getAttribute&&el.getAttribute('role')||'').toLowerCase(),r=safeRect(el);if(!visibleRect(r))return false;
    if(['header','nav','main','footer','aside','section','article','li'].includes(tag)||['navigation','banner','main','contentinfo','complementary','region','toolbar','listitem'].includes(role))return true;
    const area=(r.width*r.height)/(vw()*vh());
    if(area>.008&&area<.42&&(tag.includes('renderer')||tag.includes('view-model')||tag.includes('card')||tag.includes('tile')))return true;
    return false;
  }
  function groupName(el){const aria=clean(el.getAttribute&&el.getAttribute('aria-label'));const role=clean(el.getAttribute&&el.getAttribute('role'));const tag=(el.tagName||'group').toLowerCase();const t=ownText(el).slice(0,34);return(aria||t||tag)+(role?' ['+role+']':'');}

  let layers=[],groups=[],seen=new Set(),groupMap=new WeakMap(),domOrder=new WeakMap(),textOwners=new WeakSet(),seq=0,gseq=0,order=0;
  let diagnostics={engine:'dom-rendered-elements',visited:0,visible:0,errors:0,shadowRoots:0,media:0,text:0,boxes:0,svg:0,backgroundImages:0,roleImages:0,textNodes:0,leafText:0,pseudo:0,atomicFallback:0,rawImg:0,rawVideo:0,rawSvg:0,rawRoleImg:0,rawBgImage:0,rawTextNodes:0,fallback:false,errorSamples:[]};
  function err(e,where){diagnostics.errors++;if(diagnostics.errorSamples.length<8)diagnostics.errorSamples.push((where?where+': ':'')+(e&&e.message?e.message:String(e)));}
  function add(o){if(layers.length>=MAX_LAYERS)return;const r=o.rect||{},key=[o.kind,Math.round((r.x||0)*2),Math.round((r.y||0)*2),Math.round((r.w||0)*2),Math.round((r.h||0)*2),o.text||o.name||''].join('|');if(seen.has(key))return;seen.add(key);layers.push(Object.assign({id:'l'+(++seq),order:++order},o));}
  function registerGroup(el){if(!el||groupMap.has(el))return groupMap.get(el)||null;try{const ci=clipInfo(el,safeRect(el));if(!visibleRect(ci.rect))return null;const id='g'+(++gseq);groupMap.set(el,id);groups.push({id,name:groupName(el),tag:(el.tagName||'').toLowerCase(),role:el.getAttribute&&el.getAttribute('role')||'',rect:rectOut(ci.rect)});return id;}catch(e){err(e,'group');return null;}}
  function groupFor(el){let p=el,g=0;while(p&&p!==document.body&&p!==document.documentElement&&g++<80){if(groupCandidate(p))return registerGroup(p);p=parentEl(p);}return null;}

  function allRoots(){const roots=[document],seenRoots=new WeakSet(),out=[];while(roots.length){const root=roots.shift();if(!root||seenRoots.has(root))continue;seenRoots.add(root);out.push(root);let els=[];try{els=Array.from(root.querySelectorAll?root.querySelectorAll('*'):[]);}catch(e){err(e,'query');}for(const el of els){try{if(el.shadowRoot){diagnostics.shadowRoots++;roots.push(el.shadowRoot);}}catch(e){err(e,'shadow');}}}return out;}
  function queryAll(roots,sel){const out=[],seenEls=new WeakSet();for(const root of roots){let a=[];try{a=Array.from(root.querySelectorAll(sel));}catch(e){err(e,'selector '+sel);}for(const el of a)if(!seenEls.has(el)){seenEls.add(el);out.push(el);if(out.length>=MAX_ELEMENTS)return out;}}return out;}

  function addRaster(el,reason,kind){try{if(!isVisible(el))return;const ci=clipInfo(el,safeRect(el));if(!visibleRect(ci.rect))return;add({kind:'raster',name:label(el),groupId:groupFor(el),rect:rectOut(ci.rect),radii:ci.radii,opacity:effOpacity(el),reason,sourceKind:kind||((el.tagName||'element').toLowerCase()),assetUrl:el.currentSrc||el.src||null,order:(domOrder.get(el)||0)*10+6});diagnostics.media++;}catch(e){err(e,'raster');}}
  function addTextNode(node,el){try{const text=clean(node.nodeValue);if(!text||!isVisible(el))return;const range=document.createRange();range.selectNodeContents(node);let r=range.getBoundingClientRect();if(!visibleRect(r))return;const ci=clipInfo(el,r);if(!visibleRect(ci.rect))return;const st=safeStyle(el),before=layers.length;add({kind:'text',name:text.slice(0,70),groupId:groupFor(el),rect:rectOut(ci.rect),text,opacity:effOpacity(el),style:fontStyle(st),order:(domOrder.get(el)||0)*10+8});if(layers.length>before){textOwners.add(el);diagnostics.text++;}}catch(e){err(e,'text');}}
  function addBox(el){try{if(!isVisible(el))return;const st=safeStyle(el),r=safeRect(el),ci=clipInfo(el,r);if(!visibleRect(ci.rect))return;const b=border(st),parent=parentEl(el),ps=parent?safeStyle(parent):null,borderPaint=b.top.w+b.right.w+b.bottom.w+b.left.w>0,bgPaint=alpha(st.backgroundColor)>.01,parentBg=ps?ps.backgroundColor:'',distinctBg=bgPaint&&colorNorm(st.backgroundColor)!==colorNorm(parentBg);const area=(r.width*r.height)/(vw()*vh());if(!borderPaint&&!distinctBg)return;if(area>.72&&!isInteractive(el))return;add({kind:'box',name:label(el),groupId:groupFor(el),rect:rectOut(ci.rect),opacity:effOpacity(el),style:{backgroundColor:st.backgroundColor,border:b,radii:ci.radii,boxShadow:'none'},order:(domOrder.get(el)||0)*10+1});diagnostics.boxes++;}catch(e){err(e,'box');}}
  function needsRasterLeaf(el){const st=safeStyle(el);if(!st||elementHasVisibleText(el))return false;const bg=st.backgroundImage&&st.backgroundImage!=='none',filter=st.filter&&st.filter!=='none',back=st.backdropFilter&&st.backdropFilter!=='none',clip=st.clipPath&&st.clipPath!=='none',mask=st.maskImage&&st.maskImage!=='none',blend=st.mixBlendMode&&st.mixBlendMode!=='normal',shadow=st.boxShadow&&st.boxShadow!=='none';if(!(bg||filter||back||clip||mask||blend||shadow))return false;let visibleChildren=0;try{for(const c of Array.from(el.children||[])){if(isVisible(c)&&++visibleChildren>1)break;}}catch(_e){}return visibleChildren===0;}

  function hasRenderedBackgroundImage(el){const st=safeStyle(el);return !!st&&!!st.backgroundImage&&st.backgroundImage!=='none';}
  function roleOf(el){return clean(el.getAttribute&&el.getAttribute('role')).toLowerCase();}
  function visibleElementChildren(el){let n=0;try{for(const c of Array.from(el.children||[]))if(isVisible(c))n++;}catch(_e){}return n;}
  function elementHasVisibleText(el){try{if(ownText(el))return true;if(visibleElementChildren(el)>0)return false;return !!clean(el.innerText||el.textContent||'');}catch(_e){return false;}}
  function isRenderedMedia(el){const tag=(el.tagName||'').toUpperCase(),role=roleOf(el);if(MEDIA.has(tag)||tag==='SVG'||tag==='PICTURE'||role==='img'||role==='video')return true;if(hasRenderedBackgroundImage(el))return visibleElementChildren(el)===0&&!elementHasVisibleText(el);return false;}
  function fallbackTextForElement(el){try{if(!isVisible(el)||SKIP.has(el.tagName)||textOwners.has(el))return '';const own=ownText(el);if(own)return own;const childCount=visibleElementChildren(el);if(childCount>0)return '';const txt=clean(el.innerText||el.textContent||'');return txt.length<=500?txt:'';}catch(_e){return '';}}
  function addPseudoRaster(el,pseudo){try{if(!isVisible(el)||elementHasVisibleText(el))return;const st=safeStyle(el,pseudo);if(!st)return;const content=clean(st.content);const bg=st.backgroundImage&&st.backgroundImage!=='none';if((!content||content==='none'||content==='normal'||content==='""')&&!bg)return;const ci=clipInfo(el,safeRect(el));if(!visibleRect(ci.rect))return;add({kind:'raster',name:label(el)+' '+pseudo,groupId:groupFor(el),rect:rectOut(ci.rect),radii:ci.radii,opacity:effOpacity(el),reason:'CSS pseudo-element content',sourceKind:'pseudo',order:(domOrder.get(el)||0)*10+7});diagnostics.media++;diagnostics.pseudo++;}catch(e){err(e,'pseudo');}}

  window.__web2aeCapturePage=function(){
    layers=[];groups=[];seen=new Set();groupMap=new WeakMap();domOrder=new WeakMap();textOwners=new WeakSet();seq=0;gseq=0;order=0;diagnostics={engine:'dom-rendered-elements',visited:0,visible:0,errors:0,shadowRoots:0,media:0,text:0,boxes:0,svg:0,backgroundImages:0,roleImages:0,textNodes:0,leafText:0,pseudo:0,atomicFallback:0,rawImg:0,rawVideo:0,rawSvg:0,rawRoleImg:0,rawBgImage:0,rawTextNodes:0,fallback:false,errorSamples:[]};
    const roots=allRoots();
    const els=queryAll(roots,'*'); for(let i=0;i<els.length;i++)domOrder.set(els[i],i+1); diagnostics.visited=els.length;
    for(const el of els){try{const tag=(el.tagName||'').toUpperCase(),role=roleOf(el),st=safeStyle(el);if(tag==='IMG')diagnostics.rawImg++;if(tag==='VIDEO')diagnostics.rawVideo++;if(tag==='SVG')diagnostics.rawSvg++;if(role==='img'||role==='video')diagnostics.rawRoleImg++;if(st&&st.backgroundImage&&st.backgroundImage!=='none')diagnostics.rawBgImage++;}catch(_e){}}
    for(const root of roots){try{const tw=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);let tn;while((tn=tw.nextNode()))if(clean(tn.nodeValue))diagnostics.rawTextNodes++;}catch(_e){}}
    for(const el of els){
      if(SKIP.has(el.tagName)||!isVisible(el))continue;
      const tag=(el.tagName||'').toUpperCase(),role=roleOf(el),bg=hasRenderedBackgroundImage(el);
      if(isRenderedMedia(el)){
        let reason='Rendered media element',kind='media';
        if(tag==='SVG'){reason='SVG/icon artwork';kind='svg';diagnostics.svg++;}
        else if(bg){reason='CSS background image';kind='background-image';diagnostics.backgroundImages++;}
        else if(role==='img'||role==='video'){reason='ARIA media element';kind='aria-media';diagnostics.roleImages++;}
        addRaster(el,reason,kind);
      }
    }
    for(const root of roots){try{const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode:function(n){const p=n.parentElement||((n.getRootNode&&n.getRootNode().host)||null);return p&&clean(n.nodeValue)?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT;}});let n;while((n=walker.nextNode())){const p=n.parentElement||((n.getRootNode&&n.getRootNode().host)||null);if(p){const before=layers.length;addTextNode(n,p);if(layers.length>before)diagnostics.textNodes++;}if(layers.length>=MAX_LAYERS)break;}}catch(e){err(e,'text walker');}}
    for(const el of els){if(!isVisible(el)||SKIP.has(el.tagName))continue;const txt=fallbackTextForElement(el);if(!txt)continue;try{const r=safeRect(el),ci=clipInfo(el,r);if(!visibleRect(ci.rect))continue;const st=safeStyle(el),before=layers.length;add({kind:'text',name:txt.slice(0,70),groupId:groupFor(el),rect:rectOut(ci.rect),text:txt,opacity:effOpacity(el),style:fontStyle(st),order:(domOrder.get(el)||0)*10+8});if(layers.length>before){diagnostics.text++;diagnostics.leafText++;}}catch(e){err(e,'leaf text');}}
    for(const el of els){if(!isVisible(el)||SKIP.has(el.tagName))continue;addPseudoRaster(el,'::before');addPseudoRaster(el,'::after');}
    for(const el of els){if(SKIP.has(el.tagName))continue;if(isVisible(el))diagnostics.visible++;if(['INPUT','TEXTAREA','SELECT'].includes(el.tagName))addRaster(el,'Native form control','form-control');else if(needsRasterLeaf(el)&&!isRenderedMedia(el)&&!CONTROL.has(el.tagName))addRaster(el,'Complex leaf CSS','complex-css');else addBox(el);if(layers.length>=MAX_LAYERS)break;}
    if(layers.length<8){const step=Math.max(24,Math.min(64,Math.round(Math.min(vw(),vh())/18))),done=new WeakSet();for(let y=step/2;y<vh();y+=step)for(let x=step/2;x<vw();x+=step){let stack=[];try{stack=document.elementsFromPoint(x,y)||[];}catch(_e){}for(const el of stack){if(!el||done.has(el)||el===document.body||el===document.documentElement)continue;done.add(el);if(isRenderedMedia(el))addRaster(el,'Hit-test media fallback','hit-test');else if(needsRasterLeaf(el))addRaster(el,'Hit-test complex element','hit-test');else addBox(el);}}}
    if(layers.length<8){for(const el of els){if(!isVisible(el)||SKIP.has(el.tagName)||el===document.body||el===document.documentElement)continue;const r=safeRect(el);if(!visibleRect(r))continue;const area=(r.width*r.height)/(vw()*vh());if(area>.38||r.width<2||r.height<2)continue;const vc=visibleElementChildren(el);const atomic=vc===0||isInteractive(el)||isRenderedMedia(el);if(!atomic||elementHasVisibleText(el))continue;const before=layers.length;addRaster(el,'Atomic DOM element fallback','atomic-dom');if(layers.length>before)diagnostics.atomicFallback++;if(layers.length>=MAX_LAYERS)break;}}
    if(layers.length<2)diagnostics.fallback=true;
    const body=safeStyle(document.body),html=safeStyle(document.documentElement);const bg=body&&alpha(body.backgroundColor)>.01?body.backgroundColor:(html?html.backgroundColor:'rgb(255,255,255)');
    return{version:3,source:{url:location.href,title:document.title,capturedAt:new Date().toISOString()},viewport:{width:vw(),height:vh(),captureWidth:window.innerWidth||vw(),captureHeight:window.innerHeight||vh(),dpr:window.devicePixelRatio||1,scrollX:window.scrollX||0,scrollY:window.scrollY||0},background:bg||'rgb(255,255,255)',groups,layers,diagnostics};
  };
})();
