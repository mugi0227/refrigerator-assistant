// Store model bytes on disk without collecting a multi-GB ArrayBuffer in JS.
export async function cachedModel(name,expectedBytes) {
  if(!navigator.storage?.getDirectory)return null;
  try {const root=await navigator.storage.getDirectory();const file=await (await root.getFileHandle(name)).getFile();return file.size===expectedBytes?file:null;}
  catch(error){if(error.name==='NotFoundError')return null;throw error;}
}
export async function downloadModel({url,name,expectedBytes,signal,onProgress=()=>{}}) {
  const download=()=>storeModel({url,name,expectedBytes,signal,onProgress});
  return navigator.locks?navigator.locks.request(`fridge-model:${name}`,{signal},download):download();
}
async function storeModel({url,name,expectedBytes,signal,onProgress}) {
  signal?.throwIfAborted();
  const cached=await cachedModel(name,expectedBytes);
  if(cached){onProgress({phase:'cached',loaded:cached.size,total:cached.size});return cached;}
  if(!navigator.storage?.getDirectory)throw new Error('このブラウザではモデルの端末保存を利用できません。「ファイルから」で読み込んでください。');
  const space=await navigator.storage.estimate?.();
  if(space?.quota&&space.quota-(space.usage||0)<expectedBytes)throw new Error(`モデル保存用の空き容量が不足しています。約${Math.ceil(expectedBytes/1e6)}MB以上の空きを確保してください。`);
  const root=await navigator.storage.getDirectory();
  let writer,reader,loaded=0;
  try {
    const handle=await root.getFileHandle(name,{create:true});
    if(!handle.createWritable)throw new Error('このブラウザではモデルの保存に対応していません。「ファイルから」を利用してください。');
    writer=await handle.createWritable();
    const response=await fetch(url,{signal,credentials:'omit',referrerPolicy:'no-referrer'});
    if(!response.ok||!response.body){await response.body?.cancel();throw new Error(`モデルを取得できませんでした（HTTP ${response.status}）`);}
    reader=response.body.getReader();
    onProgress({phase:'downloading',loaded,total:expectedBytes});
    while(true){signal?.throwIfAborted();const {done,value}=await reader.read();if(done)break;loaded+=value.byteLength;
      if(loaded>expectedBytes)throw new Error('モデルのサイズが想定と異なります。ダウンロードを中止しました。');
      await writer.write(value);onProgress({phase:'downloading',loaded,total:expectedBytes});}
    signal?.throwIfAborted();
    if(loaded!==expectedBytes)throw new Error('モデルのダウンロードが途中で切れました。通信を確認して再度お試しください。');
    onProgress({phase:'saving',loaded,total:expectedBytes});
    await writer.close();
    const file=await handle.getFile();
    onProgress({phase:'saved',loaded:file.size,total:expectedBytes});return file;
  } catch(error){await reader?.cancel().catch(()=>{});await writer?.abort().catch(()=>{});await root.removeEntry(name).catch(()=>{});throw error;}
  finally{reader?.releaseLock();}
}
