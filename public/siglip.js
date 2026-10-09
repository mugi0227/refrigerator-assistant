import {MODEL,MODEL_URL,rgbaToTensor} from './siglip-core.js';
import {cachedModel,downloadModel} from './model-cache.js';
const $=selector=>document.querySelector(selector);
let worker,controller,timer,deadline,ready=false,busy=false,hasPhoto=false,started=0,photoStart=0,photoVersion=0;
const logs=[],marker='fridge-siglip-interrupted';
function log(message){logs.push(`${new Date().toISOString()} ${message}`);if(logs.length>80)logs.shift();$('#log').textContent=logs.join('\n');}
function mark(value){try{value?sessionStorage.setItem(marker,value):sessionStorage.removeItem(marker);}catch{}}
function controls(){
  $('#load').disabled=busy||ready;$('#load').textContent=ready?'✓ 読み取りの準備完了':'保存したモデルで起動';
  $('#recognize').disabled=!ready||busy||!hasPhoto;
  $('#choose').disabled=busy;$('#take').disabled=busy;$('#forget').disabled=busy;
  $('#stop').hidden=!busy;
}
function status(message){$('#status').textContent=message;}
function finish(){clearInterval(timer);clearTimeout(deadline);busy=false;mark(null);$('#progress').hidden=true;controls();}
function begin(phase,timeout){busy=true;started=performance.now();mark(phase);controls();$('#elapsed').textContent='経過 0秒';timer=setInterval(()=>$('#elapsed').textContent=`経過 ${Math.floor((performance.now()-started)/1000)}秒`,500);deadline=setTimeout(()=>fail(new Error(`${phase}が${timeout/1000}秒以内に終わりませんでした。中止しました。ログを共有してください。`)),timeout);}
function fail(error){controller?.abort();worker?.terminate();worker=null;ready=false;finish();status(error.message||String(error));log(`ERROR ${error.message||error}`);}
async function cacheStatus(){try{const file=await cachedModel(MODEL.cache,MODEL.bytes);$('#cache-note').textContent=file?'モデル：この端末に保存済み（約95MB）':'モデル：未保存（初回はWi-Fi推奨）';if(!ready&&!busy)$('#load').textContent=file?'保存したモデルで起動':'モデルを保存して起動';return file;}catch(error){log(`保存確認: ${error.message}`);return null;}}
$('#load').onclick=async()=>{
  if(busy||ready)return;
  controller=new AbortController();const signal=controller.signal;
  begin('モデルの保存',600000);status('モデルを確認しています…');
  try{
    const file=await downloadModel({url:MODEL_URL,name:MODEL.cache,expectedBytes:MODEL.bytes,signal,onProgress:p=>{
      if(signal.aborted)return;
      if(p.phase==='downloading'){
        $('#progress').hidden=false;$('#progress').value=p.loaded/p.total;
        status(`モデルを保存中 ${Math.floor(p.loaded/p.total*100)}% · ${(p.loaded/1e6).toFixed(1)} / 94.6 MB`);
      }
      if(p.phase==='cached')log('保存済みモデルを再利用');
    }});
    signal.throwIfAborted();await cacheStatus();
    clearTimeout(deadline);deadline=setTimeout(()=>fail(new Error('モデルの起動が120秒を超えたため中止しました。ログを共有してください。')),120000);
    mark('モデルの起動');$('#progress').hidden=true;status('画像モデルを起動中…');log('WASM CPU / 1 thread / モデル起動');
    worker=new Worker('./siglip-worker.js',{type:'module'});
    worker.onerror=event=>{event.preventDefault();fail(new Error(event.message||'画像処理用の実行環境を読み込めませんでした'));};
    worker.onmessage=({data})=>{
      if(data.type==='error'){fail(new Error(data.message));return;}
      if(data.type==='ready'){ready=true;finish();status('準備完了。写真を選んで読み取れます。');log(`起動 ${(data.ms/1000).toFixed(2)}秒 / 入力 ${data.inputs} / 出力 ${data.outputs}`);}
      if(data.type==='result'){
        finish();status('読み取りが終わりました。');$('#result').hidden=false;
        $('#result-title').textContent=data.ranked[0].food?`${data.ranked[0].label} かも`:'対象外の写真かもしれません';
        $('#result-note').textContent='近い候補を上から表示しています。実物と比べてください。';
        $('#candidates').replaceChildren(...data.ranked.map(item=>{const li=document.createElement('li'),name=document.createElement('strong'),score=document.createElement('span');name.textContent=item.label;score.textContent=`類似度 ${item.score.toFixed(3)}`;li.append(name,score);return li;}));
        const total=performance.now()-photoStart;$('#timing').textContent=`読み取り ${(total/1000).toFixed(2)}秒（モデル処理 ${(data.ms/1000).toFixed(2)}秒）`;
        log(`結果 ${JSON.stringify(data.ranked)} / inference ${data.ms.toFixed(0)}ms / total ${total.toFixed(0)}ms`);
      }
    };
    worker.postMessage({type:'load',file});
  }catch(error){if(signal.aborted)return;fail(error);await cacheStatus();}
};
$('#stop').onclick=()=>{controller?.abort();worker?.terminate();worker=null;ready=false;finish();status('中止しました。起動し直して再度試せます。');log('利用者が中止');cacheStatus();};
$('#take').onclick=()=>$('#camera-file').click();$('#choose').onclick=()=>$('#photo-file').click();
async function selectPhoto(event){
  const file=event.target.files?.[0];event.target.value='';if(!file)return;
  const version=++photoVersion;hasPhoto=false;$('#result').hidden=true;controls();
  if(file.size>35*1024*1024){status('35MB以下の写真を選んでください。');return;}
  let image,url;
  try{
    status('写真を準備中…');
    // HTMLImageElement supports iPhone photo orientation; canvas flattens to RGB.
    url=URL.createObjectURL(file);image=new Image();image.src=url;await image.decode();
    if(version!==photoVersion)return;
    const canvas=$('#preview'),ctx=canvas.getContext('2d',{willReadFrequently:true});
    ctx.fillStyle='#fff';ctx.fillRect(0,0,224,224);ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality='low';ctx.drawImage(image,0,0,224,224);
    canvas.hidden=false;$('#placeholder').hidden=true;hasPhoto=true;controls();
    status(ready?'写真を選びました。「この写真を読み取る」を押してください。':'写真を選びました。先にモデルを起動してください。');
    log(`画像準備 ${image.naturalWidth}×${image.naturalHeight} → 224×224`);
  }catch(error){status('写真を開けませんでした。JPEGやPNGの写真でお試しください。');log(`画像エラー ${error.message}`);}
  finally{if(url)URL.revokeObjectURL(url);if(image)image.src='';}
}
$('#camera-file').onchange=selectPhoto;$('#photo-file').onchange=selectPhoto;
$('#recognize').onclick=()=>{
  if(!ready||busy||!hasPhoto)return;
  photoStart=performance.now();$('#result').hidden=true;begin('画像の読み取り',120000);status('写真を読み取り中…');log('画像の読み取り開始');
  try{const rgba=$('#preview').getContext('2d').getImageData(0,0,224,224).data,pixels=rgbaToTensor(rgba);worker.postMessage({type:'run',pixels},[pixels.buffer]);}catch(error){fail(error);}
};
$('#forget').onclick=async()=>{
  if(busy)return;
  worker?.terminate();worker=null;ready=false;busy=true;controls();
  try{
    const remove=async()=>{const root=await navigator.storage.getDirectory();try{await root.removeEntry(MODEL.cache);}catch(error){if(error.name!=='NotFoundError')throw error;}};
    if(navigator.locks)await navigator.locks.request(`fridge-model:${MODEL.cache}`,remove);else await remove();
    status('この試用モデルを削除しました。');log('試用モデル削除');
  }catch(error){status(`削除できませんでした: ${error.message}`);}
  finally{busy=false;controls();await cacheStatus();}
};
$('#copy').onclick=async()=>{try{await navigator.clipboard.writeText(logs.join('\n'));$('#copy-status').textContent='ログをコピーしました。';}catch{$('#copy-status').textContent='コピーできませんでした。ログの表示を選択してコピーしてください。';}};
window.addEventListener('pagehide',()=>{controller?.abort();worker?.terminate();worker=null;ready=false;finish();});
window.addEventListener('pageshow',event=>{if(event.persisted){status('ページに戻りました。モデルを起動し直してください。');cacheStatus();}});
log(`SigLIP trial 1 / ${MODEL.revision} / ${navigator.userAgent} / isolated=${crossOriginIsolated}`);
try{const previous=sessionStorage.getItem(marker);if(previous){status(`前回は${previous}の途中でページが閉じられました。ログと状況を共有してください。`);log(`前回中断: ${previous}`);}else status('モデルを起動して、写真を試せます。');}catch{status('モデルを起動して、写真を試せます。');}
cacheStatus();
fetch('./siglip-labels.json').then(r=>{if(!r.ok)throw new Error('候補データの取得失敗');return r.json();}).then(data=>$('#vocabulary').textContent=data.labels.filter(x=>x.food).map(x=>x.label).join('・')).catch(error=>log(error.message));
if('serviceWorker'in navigator)navigator.serviceWorker.register('./sw.js').catch(error=>log(`オフライン準備: ${error.message}`));
