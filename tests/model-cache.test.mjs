import test from 'node:test';
import assert from 'node:assert/strict';
import {downloadModel,cachedModel} from '../public/model-cache.js';

function disk(){
  const files=new Map();let writes=0,requests=0;
  const root={
    async getFileHandle(name,{create=false}={}){
      if(!files.has(name)){if(!create)throw new DOMException('missing','NotFoundError');files.set(name,new Blob());}
      return {async getFile(){return files.get(name);},async createWritable(){const chunks=[];return {
        async write(chunk){writes++;chunks.push(chunk);},async close(){files.set(name,new Blob(chunks));},async abort(){chunks.length=0;}
      };}};
    },async removeEntry(name){files.delete(name);}
  };
  Object.defineProperty(globalThis,'navigator',{configurable:true,value:{storage:{getDirectory:async()=>root,estimate:async()=>({quota:1000,usage:0})}}});
  return {files,get writes(){return writes;},get requests(){return requests;},respond(chunks){globalThis.fetch=async()=>{requests++;return new Response(new ReadableStream({start(c){for(const chunk of chunks)c.enqueue(new Uint8Array(chunk));c.close();}}));};}};
}
const fetchOriginal=globalThis.fetch,navigatorOriginal=Object.getOwnPropertyDescriptor(globalThis,'navigator');
test.after(()=>{globalThis.fetch=fetchOriginal;if(navigatorOriginal)Object.defineProperty(globalThis,'navigator',navigatorOriginal);else delete globalThis.navigator;});

test('streamed download commits complete bytes; next load reuses disk without fetch',async()=>{
  const env=disk();env.respond([[1,2],[3,4,5]]);const progress=[];
  const options={url:'https://model.example/weights',name:'model',expectedBytes:5,onProgress:p=>progress.push(p)};
  const file=await downloadModel(options);
  assert.deepEqual([...new Uint8Array(await file.arrayBuffer())],[1,2,3,4,5]);assert.equal(env.writes,2);
  assert.deepEqual(progress.map(p=>p.phase),['downloading','downloading','downloading','saving','saved']);
  await downloadModel(options);assert.equal(env.requests,1);assert.equal(progress.at(-1).phase,'cached');
});
test('truncated and oversized downloads are removed and never reused',async()=>{
  for(const chunks of [[[1,2]],[[1,2,3,4,5,6]]]){
    const env=disk();env.respond(chunks);
    await assert.rejects(downloadModel({url:'https://model.example/weights',name:'model',expectedBytes:5}));
    assert.equal(env.files.has('model'),false);assert.equal(await cachedModel('model',5),null);
  }
});
test('cancel removes unfinished bytes, and retry downloads a complete file',async()=>{
  const env=disk();env.respond([[1,2],[3,4,5]]);const controller=new AbortController();
  await assert.rejects(downloadModel({url:'https://model.example/weights',name:'model',expectedBytes:5,signal:controller.signal,onProgress:p=>{if(p.loaded===2)controller.abort();}}),{name:'AbortError'});
  assert.equal(env.files.has('model'),false);
  assert.equal((await downloadModel({url:'https://model.example/weights',name:'model',expectedBytes:5})).size,5);
});
test('storage quota error stops before requesting the large model',async()=>{
  const env=disk();env.respond([[1,2]]);navigator.storage.estimate=async()=>({quota:3,usage:2});
  await assert.rejects(downloadModel({url:'https://model.example/weights',name:'model',expectedBytes:5}));assert.equal(env.requests,0);
});
