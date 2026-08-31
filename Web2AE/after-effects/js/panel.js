/* Web2AE v1.0.0 | Author: Elliot Mckenzie / zura */
(function(){
'use strict';
var cs=new CSInterface();
var fs=require('fs'),path=require('path'),os=require('os'),http=require('http'),childProcess=require('child_process');
var els={};['bridgeDot','bridgeStatus','bridgeDetail','restartBridge','openBrowserFolder','emptyState','captureInfo','captureTitle','captureUrl','statLayers','statGroups','statSize','statTypes','autoBuild','editableText','semanticGroups','referenceLayer','duration','fps','build','progressLabel','progressPct','progressBar','progressDetail','openWorking','copyLog','log'].forEach(function(id){els[id]=document.getElementById(id);});
var state={server:null,capture:null,workingDir:null,busy:false};
var PORT=17321,MAX_BODY=80*1024*1024;
var extensionPath=decodeURIComponent(cs.getSystemPath(SystemPath.EXTENSION)||'').replace(/^file:\/\/\//i,'');if(/^\/[A-Za-z]:\//.test(extensionPath))extensionPath=extensionPath.slice(1);extensionPath=path.normalize(extensionPath);
var browserFolder=path.join(process.env.LOCALAPPDATA||os.homedir(),'Web2AE','Browser Extension');
function log(m){var t=new Date().toLocaleTimeString();els.log.textContent+='\n['+t+'] '+m;els.log.scrollTop=els.log.scrollHeight;}
function progress(p,label,detail){p=Math.max(0,Math.min(100,p||0));els.progressBar.style.width=p+'%';els.progressPct.textContent=Math.round(p)+'%';els.progressLabel.textContent=label||'';els.progressDetail.textContent=detail||'';}
function bridgeUI(ok,text,detail){els.bridgeDot.className='dot '+(ok?'ok':'bad');els.bridgeStatus.textContent=text;els.bridgeDetail.textContent=detail||'';}
function originAllowed(req){var o=String(req.headers.origin||'');return !o||/^(chrome|moz)-extension:\/\//i.test(o);}
function cors(req,res){var o=String(req.headers.origin||'');if(/^(chrome|moz)-extension:\/\//i.test(o))res.setHeader('Access-Control-Allow-Origin',o);res.setHeader('Vary','Origin');res.setHeader('Access-Control-Allow-Headers','Content-Type');res.setHeader('Access-Control-Allow-Methods','GET,POST,OPTIONS');}
function sendJSON(req,res,code,obj){cors(req,res);res.statusCode=code;res.setHeader('Content-Type','application/json; charset=utf-8');res.end(JSON.stringify(obj));}
function startBridge(){
  try{if(state.server){try{state.server.close();}catch(e){}state.server=null;}}
  catch(e){}
  bridgeUI(false,'Starting local bridge…','Listening only on 127.0.0.1:'+PORT);
  var server=http.createServer(function(req,res){
    if(!originAllowed(req))return sendJSON(req,res,403,{ok:false,error:'Web2AE only accepts requests from its browser extension.'});
    cors(req,res);
    if(req.method==='OPTIONS'){res.statusCode=204;return res.end();}
    if(req.method==='GET'&&req.url==='/health')return sendJSON(req,res,200,{ok:true,app:'Web2AE',version:'1.0.0',busy:state.busy,hasCapture:!!state.capture});
    if(req.method==='GET'&&req.url==='/status')return sendJSON(req,res,200,{ok:true,busy:state.busy,hasCapture:!!state.capture});
    if(req.method==='POST'&&req.url==='/capture'){
      if(state.busy)return sendJSON(req,res,409,{ok:false,error:'After Effects is currently building the previous capture.'});
      var chunks=[],n=0,tooLarge=false;
      req.on('data',function(c){n+=c.length;if(n>MAX_BODY){tooLarge=true;return;}chunks.push(c);});
      req.on('end',function(){
        if(tooLarge)return sendJSON(req,res,413,{ok:false,error:'Capture is larger than the 80 MB bridge limit.'});
        try{
          var payload=JSON.parse(Buffer.concat(chunks).toString('utf8'));
          if(!payload.scene||!payload.screenshotDataUrl)throw new Error('Capture payload is incomplete.');
          receiveCapture(payload);
          sendJSON(req,res,200,{ok:true,received:true,autoBuild:els.autoBuild.checked});
        }catch(e){log('Bridge capture error: '+e.message);sendJSON(req,res,400,{ok:false,error:e.message});}
      });
      return;
    }
    sendJSON(req,res,404,{ok:false,error:'Not found'});
  });
  server.on('error',function(e){bridgeUI(false,'Bridge could not start',e.code==='EADDRINUSE'?'Port '+PORT+' is already in use. Close another Web2AE panel and retry.':e.message);log('Bridge error: '+e.message);});
  server.listen(PORT,'127.0.0.1',function(){state.server=server;bridgeUI(true,'Browser bridge ready','Waiting for live-page captures on 127.0.0.1:'+PORT);log('Local browser bridge ready on 127.0.0.1:'+PORT+'.');});
}
function receiveCapture(payload){
  state.capture=payload;var s=payload.scene,ls=s.layers||[],tc=0,bc=0,rc=0;for(var i=0;i<ls.length;i++){if(ls[i].kind==='text')tc++;else if(ls[i].kind==='box')bc++;else rc++;}els.emptyState.hidden=true;els.captureInfo.hidden=false;els.captureTitle.textContent=s.source&&s.source.title?s.source.title:'Untitled page';els.captureUrl.textContent=s.source&&s.source.url?s.source.url:'';els.statLayers.textContent=ls.length+' layers';els.statGroups.textContent=(s.groups||[]).length+' groups';els.statSize.textContent=s.viewport.width+'×'+s.viewport.height+' CSS px';if(els.statTypes)els.statTypes.textContent=tc+' text · '+bc+' shapes · '+rc+' exact';var d=s.diagnostics||{};log('Received live page: '+els.captureTitle.textContent+' · '+ls.length+' visual layers ('+tc+' text, '+bc+' shapes, '+rc+' exact-pixel fallbacks) · '+(s.groups||[]).length+' groups.');if(d.engine)log('Capture engine: '+d.engine+'.');if(d.layoutNodes!=null)log('Render-tree diagnostics: '+d.nodes+' DOM nodes · '+d.layoutNodes+' layout nodes · '+d.visible+' visible · '+d.media+' media · '+d.text+' text · '+d.boxes+' boxes · '+d.groups+' groups.');else if(d.visited!=null)log('DOM diagnostics: '+d.visited+' elements visited · '+d.visible+' visible · '+d.shadowRoots+' shadow roots · '+d.errors+' isolated errors.');if(d.errorSamples&&d.errorSamples.length)log('Capture warnings: '+d.errorSamples.slice(0,3).join(' | '));els.build.disabled=ls.length<2;if(ls.length<2){progress(0,'Capture rejected','The browser returned no visual layers. Reload the page and capture again.');log('ERROR: Web2AE refused to build a background-only capture.');return;}progress(8,'Capture received','Preparing browser screenshot and element-level layer data.');if(els.autoBuild.checked)buildCapture();
}
function dataUrlBuffer(u){var i=u.indexOf(',');if(i<0)throw new Error('Invalid screenshot data URL.');return Buffer.from(u.slice(i+1),/;base64/i.test(u.slice(0,i))?'base64':'utf8');}
function pngSize(buf){if(buf.length<24||buf.toString('ascii',1,4)!=='PNG')throw new Error('Browser screenshot is not a valid PNG.');return{w:buf.readUInt32BE(16),h:buf.readUInt32BE(20)};}
function scaleRect(r,sx,sy){return{x:r.x*sx,y:r.y*sy,w:r.w*sx,h:r.h*sy};}
function scaleBorder(b,s){var o={};['top','right','bottom','left'].forEach(function(v){var k=v;o[k]={w:(b&&b[k]?b[k].w:0)*s,c:b&&b[k]?b[k].c:'hiba(0,0,0,0)'};});return o;}
function normalizedScene(payload,dir,cb){
  var shot=dataUrlBuffer(payload.screenshotDataUrl),raw=pngSize(shot),sc=payload.scene;var captureCssW=sc.viewport.captureWidth||sc.viewport.width,captureCssH=sc.viewport.captureHeight||sc.viewport.height;var sx=raw.w/captureCssW,sy=raw.h/captureCssH,ss=(sx+sy)/2;var targetW=Math.max(1,Math.round(sc.viewport.width*sx)),targetH=Math.max(1,Math.round(sc.viewport.height*sy));var sourceFile=path.join(dir,'browser_reference.png');
  var out={version:1,name:(sc.source&&sc.source.title?sc.source.title:'Web Capture').replace(/[\\/:*?"<>|]/g,'_').slice(0,80),url:sc.source.url,width:targetW,height:targetH,sourceFile:sourceFile,background:sc.background,groups:[],layers:[]};
  (sc.groups||[]).forEach(function(g){out.groups.push({id:g.id,name:g.name,tag:g.tag,role:g.role,rect:scaleRect(g.rect,sx,sy)});});
  var pending=[];
  (sc.layers||[]).forEach(function(l,idx){var n={id:l.id,kind:l.kind,name:l.name,groupId:l.groupId||null,order:l.order||idx,rect:scaleRect(l.rect,sx,sy),opacity:l.opacity==null?1�:l.opacity,style:l.style||null,reason:l.reason||'',sourceKind:l.sourceKind||'',radii:(l.radii||[0,0,0,0]).map(function(v){return v*ss;})};
    if(n.kind==='text'){
      if(!els.editableText.checked)n.kind='raster';else if(n.style){n.style.fontSize=(n.style.fontSize||16)*ss;n.style.lineHeight=(n.style.lineHeight||0)*ss;n.style.letterSpacing=(n.style.letterSpacing||0)*ss;}
    }
    if(n.kind==='box'&&n.style){n.style.radii=(n.style.radii||[0,0,0,0]).map(function(v){return v*ss;});n.style.border=scaleBorder(n.style.border,ss);}
    if(n.kind==='raster')pending.push(n);
    out.layers.push(n);
  });
  var img=new Image();img.onload=function(){
    try{
      var canvas=document.createElement('canvas'),ctx=canvas.getContext('2d');canvas.width=targetW;canvas.height=targetH;ctx.clearRect(0,0,targetW,targetH);ctx.drawImage(img,0,0,targetW,targetH,0,0,targetW,targetH);fs.writeFileSync(sourceFile,dataUrlBuffer(canvas.toDataURL('image/png')));
      pending.forEach(function(l,i){var r=l.rect,x=Math.max(0,Math.floor(r.x)),y=Math.max(0,Math.floor(r.y)),w=Math.max(1,Math.min((targetW-x),Math.ceil(r.w))),h=Math.max(1,Math.min((targetH-y),Math.ceil(r.h)));canvas.width=w;canvas.height=h;ctx=canvas.getContext('2d');ctx.clearRect(0,0,w,h);ctx.drawImage(img,x,y,w,h,0,0,w,h);var data=canvas.toDataURL'image/png');var fp=path.join(dir,'raster_'+String(i+1).padStart(4,'0')+'.png');fs.writeFileSync(fp,dataUrlBuffer(data));l.rasterFile=fp;l.rect={x:x,y:y,w:w,h:h};});cb(null,out);
    }catch(e){cb(e);}
  };img.onerror=function(){cb(new Error('Could not decode browser screenshot for reference/raster fallbacks.'));};img.src=payload.screenshotDataUrl;
}
function jsxString(s){return '"'+String(s).replace(/\\/g,'\\\\').replace(/"/g,'\\"').replace(/\r?\n/g,'\\n')+'"';}
function buildCapture(){if(!state.capture||state.busy)return;state.busy=true;els.build.disabled=true;state.workingDir=fs.mkdtempSync(path.join(os.tmpdir(),'Web2AE-Web-'));progress(16,'Preparing capture','Writing the exact browser screenshot and raster fallbacks.');log('Working folder: '+state.workingDir);
  normalizedScene(state.capture,state.workingDir,function(err,scene){
    if(err){state.busy=false;els.build.disabled=false;progress(0,'Build failed',err.message);log('ERROR: '+err.message);return;}
    progress(58,'Building After Effects scene',scene.layers.length+' visual layers · '+scene.groups.length+' semantic groups.');var jsonPath=path.join(state.workingDir,'web_scene.json');fs.writeFileSync(jsonPath,JSON.stringify(scene,null,2),'utf8');
    var script='Web2AE.buildWebScene('+jsxString(jsonPath)+','+(els.semanticGroups.checked?'true':'false')+','+parseFloat(els.duration.value||10)+','+parseFloat(els.fps.value||25)+','+(els.referenceLayer.checked?'true':'false')+')';
    cs.evalScript(script,function(result){state.busy=false;els.build.disabled=false;if(result&&result.indexOf('ERROR:')===0){progress(0,'AE build failed',result);log(result);}else{progress(100,'After Effects comp built',result||'Done');log('AE build complete: '+result);}});
  });
}
els.build.onclick=buildCapture;els.restartBridge.onclick=startBridge;
els.openWorking.onclick=function(){if(state.workingDir&&fs.existsSync(state.workingDir))childProcess.spawn('explorer.exe',[state.workingDir],{detached:true,windowsHide:false});else log('No working folder yet.');};
els.copyLog.onclick=function(){var p=childProcess.spawn('cmd.exe',['/c','clip'],{stdio:['pipe','ignore','ignore'],windowsHide:true});p.stdin.end(els.log.textContent);};
els.openBrowserFolder.onclick=function(){if(fs.existsSync(browserFolder))childProcess.spawn('explorer.exe',[browserFolder],{detached:true,windowsHide:false});else log('Browser extension folder not found. Re-run install_windows.bat.');};
startBridge();progress(0,'Idle','Waiting for a browser capture.');
})();
