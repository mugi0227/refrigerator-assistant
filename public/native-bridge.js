import {GemmaVision,promptFor} from './vision.js';
import {CameraScanner} from './scanner.js';
import {parseBarcode} from './core.js';
export const isNative=!!globalThis.webkit?.messageHandlers?.fridge;
const pending=new Map(),listeners=new Set();let sequence=0;
if(isNative)window.fridgeNativeReceive=message=>{
  if(message.id){const item=pending.get(message.id);if(!item)return;pending.delete(message.id);clearTimeout(item.timer);if(message.error){const error=new Error(message.error);error.name=message.errorName||'Error';item.reject(error);}else item.resolve(message.result);}
  else for(const listener of listeners)listener(message);
};
export function nativeCall(action,args={},timeout=60000){
  if(!isNative)return Promise.reject(new Error('iOSアプリで利用してください'));
  const id=String(++sequence);return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{pending.delete(id);reject(new Error('iOSの処理がタイムアウトしました'));},timeout);
    pending.set(id,{resolve,reject,timer});
    try{window.webkit.messageHandlers.fridge.postMessage({id,action,args});}catch(error){clearTimeout(timer);pending.delete(id);reject(error);}
  });
}
export class NativeGemmaVision extends GemmaVision {
  constructor(onStatus,onProgress){super(onStatus,onProgress);this.native=true;
    listeners.add(message=>{if(message.type==='modelProgress'){const p=message.progress;this.report(p.phase,p.loaded||0,p.total||0);}
      if(message.type==='engineUnloaded'){this.ready=false;this.onStatus('AIのメモリを解放しました。設定から再起動できます');}});
  }
  async hasSavedModel(){return (await nativeCall('modelStatus')).saved;}
  async load(){if(this.loading||this.busy)throw new Error('AIの処理が終了してから操作してください');this.loading=true;this.started=performance.now();this.report('checking');this.onStatus('iOSのモデルを準備中…');
    try{await nativeCall('loadModel',{},45*60*1000);this.ready=true;this.report('ready');this.onStatus('Gemma 4 E2B · iOS端末内AI 準備完了');}
    catch(error){this.ready=false;this.report(error.name==='AbortError'?'cancelled':'error');throw error;}
    finally{this.loading=false;localStorage.removeItem('fridge-model-loading');}
  }
  cancelLoad(){if(this.progress?.phase==='downloading')nativeCall('cancelDownload').catch(()=>{});}
  async importModel(){if(this.loading||this.busy)throw new Error('AIの処理が終了してから操作してください');this.loading=true;this.ready=false;this.started=performance.now();this.onStatus('iOS用モデルのファイルを選んでください');
    try{await nativeCall('importModel',{},45*60*1000);}finally{this.loading=false;}
  }
  async infer(prompt,useImage,maxOutputTokens){if(!this.ready)throw new Error('設定でGemmaを起動してください');if(this.busy)throw new Error('AIは処理中です');this.busy=true;
    try{return await nativeCall('infer',{prompt,useImage,maxOutputTokens},120000);}finally{this.busy=false;}
  }
  async run(content,maxOutputTokens=256){return this.infer(content,false,maxOutputTokens);}
  async inspect(_canvas,target){return this.infer(promptFor(target),true,256);}
  cancel(){if(this.busy)nativeCall('cancelInference').catch(()=>{});}
  async unload(){await nativeCall('unloadModel');this.ready=false;}
}
export class NativeCameraScanner extends CameraScanner {
  constructor(options){super(options);this.previewLayout=()=>this.schedulePreviewLayout();
    window.addEventListener('scroll',this.previewLayout,{passive:true});window.addEventListener('resize',this.previewLayout);
    this.previewObserver=new ResizeObserver(this.previewLayout);this.previewObserver.observe(this.video.parentElement);
    const stage=this.video.parentElement;
    this.focusRing=document.createElement('span');this.focusRing.className='camera-focus-point';this.focusRing.hidden=true;this.focusRing.setAttribute('aria-hidden','true');stage.append(this.focusRing);
    this.focusControls=document.createElement('div');this.focusControls.className='camera-focus-controls';this.focusControls.hidden=true;
    const hint=document.createElement('span');hint.textContent='映像をタップしてピント合わせ';
    this.focusButton=document.createElement('button');this.focusButton.type='button';this.focusButton.className='text-button';this.focusButton.textContent='中央にピント';
    this.focusControls.append(hint,this.focusButton);stage.after(this.focusControls);
    this.focusCenter=()=>this.focusAt(0.5,0.5);this.focusButton.addEventListener('click',this.focusCenter);
    this.focusDown=event=>{if(!this.running||event.button!==0||event.target.closest('button,a,input,select,.scan-result,.camera-top'))return;
      this.focusStart={id:event.pointerId,x:event.clientX,y:event.clientY};};
    this.focusUp=event=>{const start=this.focusStart;this.focusStart=null;if(!start||start.id!==event.pointerId||Math.hypot(event.clientX-start.x,event.clientY-start.y)>8)return;
      const rect=stage.getBoundingClientRect();if(rect.width>0&&rect.height>0)this.focusAt((event.clientX-rect.x)/rect.width,(event.clientY-rect.y)/rect.height);};
    this.focusCancel=()=>{this.focusStart=null;};
    stage.addEventListener('pointerdown',this.focusDown,{passive:true});stage.addEventListener('pointerup',this.focusUp,{passive:true});stage.addEventListener('pointercancel',this.focusCancel,{passive:true});
    this.receiveFrame=message=>{if(!['cameraFrame','barcodeFrame'].includes(message.type)||!this.running)return;
      if(message.type==='cameraFrame'&&message.jpeg)this.video.src=`data:image/jpeg;base64,${message.jpeg}`;
      if(!this.paused)this.handleCodes(message.codes||[]).catch(error=>this.onStatus(error.message));};listeners.add(this.receiveFrame);}
  async start(mode='add',location='fridge'){await this.stop();await this.sounds.unlock();this.machine.mode=mode;this.machine.location=location;this.machine.reset();this.paused=false;this.failures=0;
    const epoch=++this.epoch,result=await nativeCall('cameraStart');if(epoch!==this.epoch){await nativeCall('cameraStop');return;}this.running=true;
    this.nativePreview=result.nativePreview===true;document.documentElement.classList.toggle('native-camera-preview',this.nativePreview);this.focusControls.hidden=false;this.schedulePreviewLayout();
    this.onStatus(this.vision.ready?'読み取り中 · iOS端末内で処理':'バーコード読み取り中 · Gemmaは未起動');
    this.timer=setInterval(()=>{if(!this.paused)this.machine.tick();},100);this.visionLoop(epoch);
  }
  async handleCodes(codes){await super.handleCodes(codes);
    const valid=[...new Set(codes.map(c=>parseBarcode(c.text)?.barcode).filter(Boolean))];
    if(this.running&&!this.paused&&valid.length===1)this.onStatus(`バーコードを読み取りました：${valid[0]}`);
  }
  async focusAt(x,y){if(!this.running||!this.nativePreview)return;x=Math.min(1,Math.max(0,x));y=Math.min(1,Math.max(0,y));
    this.focusRing.style.left=`${x*100}%`;this.focusRing.style.top=`${y*100}%`;this.focusRing.hidden=false;
    clearTimeout(this.focusTimer);this.focusTimer=setTimeout(()=>{this.focusRing.hidden=true;},1000);
    try{await nativeCall('cameraFocus',{x,y},10000);}catch(error){if(this.running)this.onStatus(error.message);}
  }
  capture(canvas,max=960){const w=this.video.naturalWidth,h=this.video.naturalHeight;if(!w||!h)return false;const side=Math.min(w,h)*0.8,out=Math.min(max,Math.round(side));canvas.width=out;canvas.height=out;canvas.getContext('2d').drawImage(this.video,(w-side)/2,(h-side)/2,side,side,0,0,out,out);return true;}
  schedulePreviewLayout(){if(!this.nativePreview||this.layoutFrame)return;this.layoutFrame=requestAnimationFrame(()=>{
    this.layoutFrame=0;if(!this.running||!this.nativePreview)return;
    const stage=this.video.parentElement,rect=stage.getBoundingClientRect(),radius=parseFloat(getComputedStyle(stage).borderRadius)||0;
    nativeCall('cameraPreviewLayout',{x:rect.x,y:rect.y,width:rect.width,height:rect.height,radius,visible:!!stage.getClientRects().length}).catch(()=>{});
  });}
  async stop(){document.documentElement.classList.remove('native-camera-preview');this.nativePreview=false;
    this.focusStart=null;clearTimeout(this.focusTimer);this.focusRing.hidden=true;this.focusControls.hidden=true;
    cancelAnimationFrame(this.layoutFrame);this.layoutFrame=0;await super.stop();if(isNative)await nativeCall('cameraStop').catch(()=>{});}
  async destroy(){await super.destroy();listeners.delete(this.receiveFrame);this.previewObserver.disconnect();window.removeEventListener('scroll',this.previewLayout);window.removeEventListener('resize',this.previewLayout);
    const stage=this.video.parentElement;stage.removeEventListener('pointerdown',this.focusDown);stage.removeEventListener('pointerup',this.focusUp);stage.removeEventListener('pointercancel',this.focusCancel);
    this.focusButton.removeEventListener('click',this.focusCenter);this.focusRing.remove();this.focusControls.remove();}
}
