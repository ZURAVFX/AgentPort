/* Web2AE v1.0.0 | Author: Elliot Mckenzie / zura */
var Web2AE = Web2AE || {};
(function(ns){
function readFile(p){var f=new File(p);f.encoding='UTF-8';if(!f.open('r'))throw new Error('Cannot open '+p);var s=f.read();f.close();return s;}
function safeName(s){return String(s||'Layer').replace(/[\\\/:*?"<>|]/g,'_').replace(/\s+/g,' ').substr(0,90)||'Layer';}
function clamp(v,a,b){v=Number(v);if(!isFinite(v))v=a;return Math.max(a,Math.min(b,v));}
function parseColor(s){
  s=String(s||'').toLowerCase();var m=s.match(/rgba?\(([^)]+)\)/);if(m){var p=m[1].split(',');return{rgb:[clamp(parseFloat(p[0])/255,0,1),clamp(parseFloat(p[1])/255,0,1),clamp(parseFloat(p[2])/255,0,1)],a:p.length>3?clamp(parseFloat(p[3]),0,1):1};}
  m=s.match(/^#([0-9a-f]{6})/);if(m){var n=parseInt(m[1],16);return{rgb:[((n>>16)&255)/255,((n>>8)&255)/255,(n&255)/255],a:1};}
  return{rgb:[1,1,1],a:s==='transparent'?0:1};
}
function makeComp(name,w,h,dur,fps,folder){var c=app.project.items.addComp(safeName(name),Math.max(4,Math.round(w)),Math.max(4,Math.round(h)),1,dur,fps);if(folder)c.parentFolder=folder;return c;}
function ensureFolder(name){return app.project.items.addFolder(safeName(name));}
function importFootage(filePath,folder,cache){if(cache[filePath])return cache[filePath];var f=new File(filePath);if(!f.exists)throw new Error('Missing raster file: '+filePath);var item=app.project.importFile(new ImportOptions(f));if(folder)item.parentFolder=folder;cache[filePath]=item;return item;}
function addRectFillGroup(root,name,x,y,w,h,color,roundness){
  var g=root.addProperty('ADBE Vector Group');g.name=name;var c=g.property('ADBE Vectors Group');var r=c.addProperty('ADBE Vector Shape - Rect');r.property('ADBE Vector Rect Size').setValue([Math.max(.1,w),Math.max(.1,h)]);r.property('ADBE Vector Rect Position').setValue([x,y]);try{r.property('ADBE Vector Rect Roundness').setValue(Math.max(0,roundness||0));}catch(e){}
  var f=c.addProperty('ADBE Vector Graphic - Fill');f.property('ADBE Vector Fill Color').setValue(color.rgb);f.property('ADBE Vector Fill Opacity').setValue(color.a*100);return g;
}
function radiiEqual(r){return Math.abs((r[0]||0)-(r[1]||0))<.2&&Math.abs((r[0]||0)-(r[2]||0))<.2&&Math.abs((r[0]||0)-(r[3]||0))<.2;}
function roundedRectShape(w,h,r){
  var k=.5522847498307936,tl=clamp(r[0]||0,0,Math.min(w,h)/2),tr=clamp(r[1]||0,0,Math.min(w,h)/2),br=clamp(r[2]||0,0,Math.min(w,h)/2),bl=clamp(r[3]||0,0,Math.min(w,h)/2);
  var sh=new Shape();sh.closed=true;sh.vertices=[[tl,0],[w-tr,0],[w,tr],[w,h-br],[w-br,h],[bl,h],[0,h-bl],[0,tl]];
  sh.inTangents=[[-k*tl,0],[0,0],[0,-k*tr],[0,0],[k*br,0],[0,0],[0,k*bl],[0,0]];
  sh.outTangents=[[0,0],[k*tr,0],[0,0],[0,k*br],[0,0],[-k*bl,0],[0,0],[0,-k*tl]];return sh;
}
function addRoundedPathGroup(root,name,w,h,r,fill,stroke,strokeWidth){
  var g=root.addProperty('ADBE Vector Group');g.name=name;var c=g.property('ADBE Vectors Group');var p=c.addProperty('ADBE Vector Shape - Group');p.property('ADBE Vector Shape').setValue(roundedRectShape(w,h,r));
  if(fill&&fill.a>.001){var f=c.addProperty('ADBE Vector Graphic - Fill');f.property('ADBE Vector Fill Color').setValue(fill.rgb);f.property('ADBE Vector Fill Opacity').setValue(fill.a*100);}
  if(stroke&&stroke.a>.001&&strokeWidth>.01){var st=c.addProperty('ADBE Vector Graphic - Stroke');st.property('ADBE Vector Stroke Color').setValue(stroke.rgb);st.property('ADBE Vector Stroke Opacity').setValue(stroke.a*100);st.property('ADBE Vector Stroke Width').setValue(strokeWidth);}
  return g;
}
function borderSimilar(b){if(!b)return false;var w=[b.top.w,b.right.w,b.bottom.w,b.left.w],c=[b.top.c,b.right.c,b.bottom.c,b.left.c];return Math.abs(w[0]-w[1])<.2&&Math.abs(w[0]-w[2])<.2&&Math.abs(w[0]-w[3])<.2&&c[0]===c[1]&&c[0]===c[2]&&c[0]===c[3];}
function addBox(comp,l,ox,oy){
  var r=l.rect,s=l.style||{},x=r.x-ox,y=r.y-oy,w=r.w,h=r.h;var sh=comp.layers.addShape();sh.name=safeName(l.name||'Box');var root=sh.property('ADBE Root Vectors Group');var bg=parseColor(s.backgroundColor);var rad=s.radii||[0,0,0,0];var round=Math.min(rad[0]||0,rad[1]||0,rad[2]||0,rad[3]||0);
  if(bg.a>.001){if(radiiEqual(rad))addRectFillGroup(root,'Background',w/2,h/2,w,h,bg,round);else addRoundedPathGroup(root,'Background',w,h,rad,bg,null,0);}
  var b=s.border||{};
  if(b.top&&borderSimilar(b)&&b.top.w>.01){var bc=parseColor(b.top.c);if(radiiEqual(rad)){var g=root.addProperty('ADBE Vector Group');g.name='Border';var c=g.property('ADBE Vectors Group');var rr=c.addProperty('ADBE Vector Shape - Rect');rr.property('ADBE Vector Rect Size').setValue([w,h]);rr.property('ADBE Vector Rect Position').setValue([w/2,h/2]);try{rr.property('ADBE Vector Rect Roundness').setValue(round);}catch(e){}var st=c.addProperty('ADBE Vector Graphic - Stroke');st.property('ADBE Vector Stroke Color').setValue(bc.rgb);st.property('ADBE Vector Stroke Opacity').setValue(bc.a*100);st.property('ADBE Vector Stroke Width').setValue(b.top.w);}else addRoundedPathGroup(root,'Border',w,h,rad,null,bc,b.top.w);}
  else if(b.top){
    var sides=[['top',w/2,b.top.w/2,w,b.top.w],['right',w-b.right.w/2,h/2,b.right.w,h],['bottom',w/2,h-b.bottom.w/2,w,b.bottom.w],['left',b.left.w/2,h/2,b.left.w,h]];
    for(var i=0;i<sides.length;i++){var q=sides[i],bb=b[q[0]];if(bb&&bb.w>.01){var cc=parseColor(bb.c);if(cc.a>.001)addRectFillGroup(root,'Border '+q[0],q[1],q[2],q[3],q[4],cc,0);}}
  }
  sh.property('ADBE Transform Group').property('ADBE Position').setValue([x,y]);sh.property('ADBE Transform Group').property('ADBE Opacity').setValue(clamp((l.opacity==null?1:l.opacity)*100,0,100));try{sh.comment='Web2AE DOM box · '+l.id;}catch(e){}return sh;
}
function applyTextStyle(td,s){
  try{td.fontSize=Math.max(1,s.fontSize||16);}catch(e){}try{if(s.fontFamily)td.font=s.fontFamily;}catch(e){}var c=parseColor(s.color);try{td.applyFill=true;td.fillColor=c.rgb;}catch(e){}try{td.applyStroke=false;}catch(e){}try{if(s.lineHeight>0){td.autoLeading=false;td.leading=s.lineHeight;}}catch(e){}try{if(s.letterSpacing)td.tracking=(s.letterSpacing/(s.fontSize||16))*1000;}catch(e){}try{if(Number(s.fontWeight)>=600)td.fauxBold=true;}catch(e){}try{if(String(s.fontStyle).toLowerCase()==='italic')td.fauxItalic=true;}catch(e){}try{if(s.textAlign==='center')td.justification=ParagraphJustification.CENTER_JUSTIFY;else if(s.textAlign==='right'||s.textAlign==='end')td.justification=ParagraphJustification.RIGHT_JUSTIFY;else td.justification=ParagraphJustification.LEFT_JUSTIFY;}catch(e){}return td;
}
function addText(comp,l,ox,oy){
  var r=l.rect,s=l.style||{},text=String(l.text||l.name||'');var useBox=r.h>((s.fontSize||16)*1.55)||text.indexOf('\n')>=0;var tl=useBox?comp.layers.addBoxText([Math.max(2,r.w),Math.max(2,r.h)],text):comp.layers.addText(text);tl.name=safeName(l.name||text.substr(0,40)||'Text');var p=tl.property('ADBE Text Properties').property('ADBE Text Document');var td=p.value;td.text=text;td=applyTextStyle(td,s);p.setValue(td);
  try{var sr=tl.sourceRectAtTime(0,false);tl.property('ADBE Transform Group').property('ADBE Position').setValue([r.x-ox-sr.left,r.y-oy-sr.top]);}catch(e){tl.property('ADBE Transform Group').property('ADBE Position').setValue([r.x-ox,r.y-oy]);}
  tl.property('ADBE Transform Group').property('ADBE Opacity').setValue(clamp((l.opacity==null?1:l.opacity)*100,0,100));try{tl.comment='Web2AE live DOM text · '+l.id;}catch(e){}return tl;
}
function applyRasterMask(rl,item,l){var rad=l.radii||[0,0,0,0],has=false;for(var i=0;i<4;i++)if((rad[i]||0)>.2)has=true;if(!has)return;try{var sx=item.width/Math.max(.1,l.rect.w),sy=item.height/Math.max(.1,l.rect.h),sr=[(rad[0]||0)*sx,(rad[1]||0)*sx,(rad[2]||0)*sx,(rad[3]||0)*sx];var masks=rl.property('ADBE Mask Parade');var m=masks.addProperty('ADBE Mask Atom');m.name='CSS rounded clip';m.property('ADBE Mask Shape').setValue(roundedRectShape(item.width,item.height,sr));}catch(e){}}
function addRaster(comp,l,ox,oy,folder,cache){var r=l.rect;var item=importFootage(l.rasterFile,folder,cache);var rl=comp.layers.add(item);rl.name=safeName(l.name||l.sourceKind||'Raster');applyRasterMask(rl,item,l);var sx=r.w/item.width*100,sy=r.h/item.height*100;rl.property('ADBE Transform Group').property('ADBE Scale').setValue([sx,sy]);rl.property('ADBE Transform Group').property('ADBE Position').setValue([r.x-ox+r.w/2,r.y-oy+r.h/2]);rl.property('ADBE Transform Group').property('ADBE Opacity').setValue(clamp((l.opacity==null?1:l.opacity)*100,0,100));try{rl.comment='Web2AE exact element pixels · '+(l.reason||'unsupported CSS')+' · '+l.id;}catch(e){}return rl;}
function addRecord(comp,l,ox,oy,folder,cache){if(l.kind==='text')return addText(comp,l,ox,oy);if(l.kind==='box')return addBox(comp,l,ox,oy);return addRaster(comp,l,ox,oy,folder,cache);}
function groupBounds(g,layers,W,H){if(g&&g.rect&&g.rect.w>1&&g.rect.h>1)return{x:clamp(g.rect.x,0,W-1),y:clamp(g.rect.y,0,H-1),w:clamp(g.rect.w,1,W),h:clamp(g.rect.h,1,H)};var minX=W,minY=H,maxX=0,maxY=0;for(var i=0;i<layers.length;i++){var r=layers[i].rect;minX=Math.min(minX,r.x);minY=Math.min(minY,r.y);maxX=Math.max(maxX,r.x+r.w);maxY=Math.max(maxY,r.y+r.h);}return{x:minX,y:minY,w:Math.max(1,maxX-minX),h:Math.max(1,maxY-minY)};}
function minOrder(a){var n=999999999;for(var i=0;i<a.length;i++)n=Math.min(n,Number(a[i].order)||0);return n===999999999?0:n;}
function addBackground(comp,color){var c=parseColor(color);if(c.a<=.001)return null;var l=comp.layers.addShape();l.name='PAGE BACKGROUND';var root=l.property('ADBE Root Vectors Group');addRectFillGroup(root,'Background',comp.width/2,comp.height/2,comp.width,comp.height,c,0);l.property('ADBE Transform Group').property('ADBE Position').setValue([0,0]);l.moveToEnd();return l;}
ns.buildWebScene=function(jsonPath,precomp,dur,fps,keepReference){
  try{
    app.beginUndoGroup('Web2AE — Web to AE');if(!app.project)app.newProject();var s=eval('('+readFile(jsonPath)+')');var W=Math.max(4,Math.round(s.width)),H=Math.max(4,Math.round(s.height)),folder=ensureFolder('Web2AE — '+(s.name||'Web Capture')),assets=app.project.items.addFolder('Web Capture Assets');assets.parentFolder=folder;var cache={};var master=makeComp(s.name||'Web Capture',W,H,dur||10,fps||25,folder);addBackground(master,s.background);
    var ref=importFootage(s.sourceFile,assets,cache);if(keepReference){var rl=master.layers.add(ref);rl.name='REFERENCE — Browser Capture';rl.property('ADBE Transform Group').property('ADBE Position').setValue([W/2,H/2]);try{rl.guideLayer=true;rl.enabled=false;rl.shy=true;rl.locked=true;}catch(e){}}
    var layers=s.layers||[],groups=s.groups||[],byGroup={},ungrouped=[];for(var i=0;i<layers.length;i++){var l=layers[i];if(precomp&&l.groupId){if(!byGroup[l.groupId])byGroup[l.groupId]=[];byGroup[l.groupId].push(l);}else ungrouped.push(l);}
    var masterItems=[];
    if(precomp){for(var gi=0;gi<groups.length;gi++){var g=groups[gi],gl=byGroup[g.id]||[];if(!gl.length)continue;gl.sort(function(a,b){return (a.order||0)-(b.order||0);});var gb=groupBounds(g,gl,W,H);var pc=makeComp(g.name||('Group '+(gi+1)),gb.w,gb.h,dur||10,fps||25,folder);for(var k=0;k<gl.length;k++)addRecord(pc,gl[k],gb.x,gb.y,assets,cache);masterItems.push({kind:'group',order:minOrder(gl),comp:pc,name:g.name,b:gb});}}
    for(var u=0;u<ungrouped.length;u++)masterItems.push({kind:'layer',order:ungrouped[u].order||0,layer:ungrouped[u]});masterItems.sort(function(a,b){return a.order-b.order;});
    for(var mi=0;mi<masterItems.length;mi++){var it=masterItems[mi];if(it.kind==='group'){var pl=master.layers.add(it.comp);pl.name=safeName(it.name||'Group');pl.property('ADBE Transform Group').property('ADBE Position').setValue([it.b.x+it.b.w/2,it.b.y+it.b.h/2]);try{pl.comment='Web2AE semantic DOM precomp';}catch(e){}}else addRecord(master,it.layer,0,0,assets,cache);}
    master.openInViewer();app.endUndoGroup();var raster=0,text=0,box=0;for(var q=0;q<layers.length;q++){if(layers[q].kind==='raster')raster++;else if(layers[q].kind==='text')text++;else if(layers[q].kind==='box')box++;}return master.name+' · '+W+'×'+H+' · '+layers.length+' layers ('+text+' text, '+box+' shapes, '+raster+' exact-pixel fallbacks) · '+(precomp?groups.length:0)+' groups';
  }catch(e){try{app.endUndoGroup();}catch(_e){}return 'ERROR: '+e.toString()+' @ line '+(e.line||'?');}
};
})(Web2AE);
