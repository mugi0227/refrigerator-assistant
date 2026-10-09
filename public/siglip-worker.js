import * as ort from './vendor/ort-1.30.0/ort.wasm.min.mjs';
import {MODEL,rankCandidates} from './siglip-core.js';
let session,catalog;
ort.env.wasm.wasmPaths=new URL('./vendor/ort-1.30.0/',import.meta.url).href;
// Single thread also works without SharedArrayBuffer in Safari/PWA.
ort.env.wasm.numThreads=1;
ort.env.wasm.proxy=false;
self.onmessage=async({data})=>{
  try{
    if(data.type==='load'){
      const response=await fetch('./siglip-labels.json');
      if(!response.ok)throw new Error('候補データを取得できません');
      const labels=await response.json();
      if(labels.revision!==MODEL.revision)throw new Error('候補データの版が一致しません。ページを再読み込みしてください');
      catalog=labels.labels;
      const started=performance.now();
      session=await ort.InferenceSession.create(await data.file.arrayBuffer(),{executionProviders:['wasm'],graphOptimizationLevel:'all'});
      self.postMessage({type:'ready',ms:performance.now()-started,inputs:session.inputNames,outputs:session.outputNames});
    }else if(data.type==='run'){
      if(!session)throw new Error('先にモデルを起動してください');
      const started=performance.now();
      const tensor=new ort.Tensor('float32',data.pixels,[1,3,224,224]);
      const outputs=await session.run({pixel_values:tensor});
      try{
        const vector=outputs.image_embeds??outputs.pooler_output;
        if(!vector||vector.data.length!==768)throw new Error(`特徴量の形式が想定と異なります: ${Object.keys(outputs).join(', ')}`);
        const ranked=rankCandidates(vector.data,catalog);
        self.postMessage({type:'result',ranked:ranked.slice(0,3),ms:performance.now()-started});
      }finally{tensor.dispose();for(const value of Object.values(outputs))value.dispose();}
    }
  }catch(error){self.postMessage({type:'error',message:error.message||String(error)});}
};
