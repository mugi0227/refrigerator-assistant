import {GemmaVision,promptFor} from './vision.js';
import {CameraScanner} from './scanner.js';
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
  async importModel(){if(this.loading||this.busy)throw new Error('AIの処理が終了してから操作してください');this.loading=true;this.started=performance.now();this.onStatus('iOS用モデルのファイルを選んでください');
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
  constructor(options){super(options);listeners.add(message=>{if(message.type!=='cameraFrame'||!this.running)return;this.video.src=`data:image/jpeg;base64,${message.jpeg}`;
    if(!this.paused)this.handleCodes(message.codes||[]).catch(error=>this.onStatus(error.message));});}
  async start(mode='add',location='fridge'){await this.stop();await this.sounds.unlock();this.machine.mode=mode;this.machine.location=location;this.machine.reset();this.paused=false;this.failures=0;
    const epoch=++this.epoch;await nativeCall('cameraStart');if(epoch!==this.epoch){await nativeCall('cameraStop');return;}this.running=true;
    this.onStatus(this.vision.ready?'読み取り中 · iOS端末内で処理':'バーコード読み取り中 · Gemmaは未起動');
    this.timer=setInterval(()=>{if(!this.paused)this.machine.tick();},100);this.visionLoop(epoch);
  }
  capture(canvas,max=960){const w=this.video.naturalWidth,h=this.video.naturalHeight;if(!w||!h)return false;const side=Math.min(w,h)*0.8,out=Math.min(max,Math.round(side));canvas.width=out;canvas.height=out;canvas.getContext('2d').drawImage(this.video,(w-side)/2,(h-side)/2,side,side,0,0,out,out);return true;}
  async stop(){await super.stop();if(isNative)await nativeCall('cameraStop').catch(()=>{});}
}
