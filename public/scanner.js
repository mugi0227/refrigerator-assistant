import {parseBarcode,parseObservation,ScanMachine,canonicalName} from './core.js';
export class Sounds {
  constructor(){this.enabled=true;this.context=null;}
  async unlock(){try{this.context??=new (window.AudioContext||window.webkitAudioContext)();await this.context.resume();}catch{/* Visual status always remains available. */}}
  play(kind){if(!this.enabled||!this.context||this.context.state!=='running')return;const ctx=this.context,now=ctx.currentTime;
    const notes=kind==='registered'?[660,880]:kind==='error'?[240]:[1040];
    notes.forEach((hz,i)=>{const osc=ctx.createOscillator(),gain=ctx.createGain(),t=now+i*0.105;osc.type='sine';osc.frequency.value=hz;gain.gain.setValueAtTime(0,t);gain.gain.linearRampToValueAtTime(0.12,t+0.012);gain.gain.exponentialRampToValueAtTime(0.001,t+0.13);osc.connect(gain).connect(ctx.destination);osc.start(t);osc.stop(t+0.14);});
  }
}
/** One video preview, independent barcode loop, serialized VLM loop, no backlog. */
export class CameraScanner {
  constructor({video,vision,sounds,getState,onChange,onCommit,onStatus,onMetric}) {
    Object.assign(this,{video,vision,sounds,getState,onStatus,onMetric});this.running=false;this.paused=false;this.epoch=0;this.worker=null;this.native=null;this.barcodeBusy=false;this.visionBusy=false;this.lookupCache=new Map();this.lookupTimes=new Map();
    this.canvas=document.createElement('canvas');this.barcodeCanvas=document.createElement('canvas');
    this.machine=new ScanMachine({onChange,onDetect:()=>sounds.play('detected'),onCommit});
    this.visibility=()=>{if(document.hidden)this.stop();};document.addEventListener('visibilitychange',this.visibility);
  }
  async start(mode='add',location='fridge') {
    await this.stop();await this.sounds.unlock();
    if(!isSecureContext||!navigator.mediaDevices?.getUserMedia)throw new Error('カメラにはHTTPSが必要です。CloudflareのURLで開いてください。');
    this.machine.mode=mode;this.machine.location=location;this.machine.reset();this.paused=false;this.barcodeFailed=false;this.failures=0;
    const epoch=++this.epoch;
    this.stream=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:960}}});
    if(epoch!==this.epoch){this.stream.getTracks().forEach(t=>t.stop());return;}
    this.video.srcObject=this.stream;await this.video.play();this.running=true;
    const track=this.stream.getVideoTracks()[0];track.onended=()=>this.stop();
    await this.setupBarcode();
    try{this.wakeLock=await navigator.wakeLock?.request('screen');}catch{/* optional */}
    this.onStatus(this.vision.ready?'読み取り中 · 画像は端末内で処理':'バーコード読み取り中 · Gemmaは未起動');
    this.timer=setInterval(()=>{if(!this.paused)this.machine.tick();},100);this.barcodeLoop(epoch);this.visionLoop(epoch);
  }
  async setupBarcode() {
    if(this.worker||this.native)return;
    if('BarcodeDetector'in window){try{const supported=await BarcodeDetector.getSupportedFormats();const formats=['ean_13','ean_8','upc_a','qr_code','data_matrix','code_128'].filter(f=>supported.includes(f));if(formats.includes('ean_13'))this.native=new BarcodeDetector({formats});}catch{/* use WASM */}}
    if(!this.native){this.worker=new Worker('./barcode-worker.js',{type:'module'});
      this.worker.onmessage=({data})=>{this.barcodeBusy=false;if(data.error){this.barcodeFailed=true;this.onStatus('バーコード読取エラー。AI・手動登録は利用できます');return;}if(data.id!==this.epoch||!this.running||this.paused)return;this.handleCodes(data.codes);};
      this.worker.onerror=()=>{this.barcodeBusy=false;this.barcodeFailed=true;this.onStatus('バーコード実行環境を読み込めませんでした');};
    }
  }
  capture(canvas,max=960) {
    const w=this.video.videoWidth,h=this.video.videoHeight;if(!w||!h)return false;
    // Center 80% ROI keeps other groceries outside the recognition target.
    const side=Math.min(w,h)*0.8, out=Math.min(max,Math.round(side));canvas.width=out;canvas.height=out;
    canvas.getContext('2d',{willReadFrequently:true}).drawImage(this.video,(w-side)/2,(h-side)/2,side,side,0,0,out,out);return true;
  }
  async barcodeLoop(epoch) {
    if(!this.running||epoch!==this.epoch)return;
    if(!this.paused&&!this.barcodeBusy&&!this.barcodeFailed&&this.capture(this.barcodeCanvas,800)){
      this.barcodeBusy=true;
      if(this.native){try{const codes=await this.native.detect(this.barcodeCanvas);if(epoch===this.epoch&&!this.paused)this.handleCodes(codes.map(c=>({text:c.rawValue,format:c.format})));}catch{this.onStatus('バーコードを読み取れませんでした');}finally{this.barcodeBusy=false;}}
      else if(this.worker){const image=this.barcodeCanvas.getContext('2d').getImageData(0,0,this.barcodeCanvas.width,this.barcodeCanvas.height);this.worker.postMessage({id:epoch,buffer:image.data.buffer,width:image.width,height:image.height},[image.data.buffer]);}
    }
    this.barcodeTimer=setTimeout(()=>this.barcodeLoop(epoch),220);
  }
  async handleCodes(codes) {
    const valid=codes.map(c=>parseBarcode(c.text)).filter(Boolean);const unique=[...new Map(valid.map(v=>[v.barcode,v])).values()];
    if(unique.length!==1)return;const data=unique[0],state=this.getState();
    let known=state.productCache[data.barcode]||this.lookupCache.get(data.barcode);
    if(!known){const existing=state.items.find(i=>i.barcode===data.barcode);if(existing)known={name:existing.name,kind:existing.kind,unit:existing.unit};}
    this.machine.barcode(data,known);
    // OFF is optional and sends ONLY the numeric barcode. No arbitrary scanned URL requests.
    if(!known&&state.settings.externalLookup&&Date.now()-(this.lookupTimes.get(data.barcode)||0)>60000){
      this.lookupTimes.set(data.barcode,Date.now());const epoch=this.epoch,barcode=data.barcode;
      try{const code=barcode.startsWith('0')?barcode.slice(1):barcode;const response=await fetch(`https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=product_name,product_name_ja`,{signal:AbortSignal.timeout(5000),credentials:'omit',referrerPolicy:'no-referrer'});
        if(!response.ok)return;const json=await response.json(),name=json.product?.product_name_ja||json.product?.product_name;
        if(name){known={name:canonicalName(name),kind:'packaged',unit:'個'};this.lookupCache.set(barcode,known);
          if(epoch===this.epoch&&this.machine.target?.barcode===barcode&&!this.machine.pending){Object.assign(this.machine.target,known);this.machine.emit();}}
      }catch{/* Missing product coverage/network must not stop the camera. */}
    }
  }
  async visionLoop(epoch) {
    if(!this.running||epoch!==this.epoch)return;
    if(!this.paused&&this.vision.ready&&!this.vision.busy&&!this.visionBusy&&this.capture(this.canvas)){
      this.visionBusy=true;const revision=this.machine.revision;
      try{const result=await this.vision.inspect(this.canvas,this.machine.target);
        if(epoch!==this.epoch||this.paused||revision!==this.machine.revision)return;
        this.onMetric({ms:result.ms,text:result.text});this.machine.observe(parseObservation(result.text));this.failures=0;
      }catch(error){if(epoch===this.epoch&&!this.paused){this.failures=(this.failures||0)+1;this.onStatus(this.failures>=3?'AI読み取りを一時停止しました。再開または手動登録してください':`読み直しています：${error.message}`);if(this.failures>=3)this.paused=true;}}
      finally{this.visionBusy=false;if(this.running&&epoch===this.epoch)this.visionTimer=setTimeout(()=>this.visionLoop(epoch),Number(this.getState().settings.interval)||1200);}
    }else this.visionTimer=setTimeout(()=>this.visionLoop(epoch),500);
  }
  setPaused(value){this.paused=value;if(value){this.vision.cancel();this.machine.revision++;}else{this.failures=0;if(this.machine.pending)this.machine.pending.deadline=Date.now()+5000;}}
  async stop(){this.running=false;this.epoch++;this.vision.cancel();clearInterval(this.timer);clearTimeout(this.barcodeTimer);clearTimeout(this.visionTimer);
    if(this.stream){this.stream.getTracks().forEach(t=>{t.onended=null;t.stop();});this.stream=null;}
    if(this.video)this.video.srcObject=null;if(this.worker){this.worker.terminate();this.worker=null;}this.barcodeBusy=false;if(this.wakeLock){await this.wakeLock.release().catch(()=>{});this.wakeLock=null;}
    // Pending registration is canceled on backgrounding, navigation or camera shutdown.
    this.machine?.reset();this.onStatus?.('カメラ停止中');
  }
  async destroy(){await this.stop();this.worker?.terminate();document.removeEventListener('visibilitychange',this.visibility);}
}
