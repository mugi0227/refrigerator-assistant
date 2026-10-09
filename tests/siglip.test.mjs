import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {MODEL,rgbaToTensor,rankCandidates} from '../public/siglip-core.js';
test('RGB values use SigLIP normalization and channel-first order',()=>{
  const result=rgbaToTensor(new Uint8ClampedArray([255,0,128,255]),1);
  assert.deepEqual(Array.from(result).map(x=>Number(x.toFixed(5))),[1,-1,0.00392]);
  assert.throws(()=>rgbaToTensor(new Uint8Array(4)),/サイズ/);
});
test('cosine ranking is independent of magnitude and rejects incompatible output',()=>{
  assert.deepEqual(rankCandidates([1,0],[{label:'other',food:false,embedding:[0,5]},{label:'apple',food:true,embedding:[3,0]}]).map(x=>x.label),['apple','other']);
  assert.throws(()=>rankCandidates([0,0],[]),/特徴量/);
  assert.throws(()=>rankCandidates([1,0],[{embedding:[1]}]),/次元/);
});
test('checked-in candidate vectors belong to the pinned model',async()=>{
  const data=JSON.parse(await readFile(new URL('../public/siglip-labels.json',import.meta.url)));
  assert.equal(data.revision,MODEL.revision);
  assert.equal(new Set(data.labels.map(x=>x.label)).size,data.labels.length);
  assert.equal(data.labels.filter(x=>x.food).length,35);
  for(const row of data.labels){assert.equal(row.embedding.length,768);assert.ok(Math.abs(Math.hypot(...row.embedding)-1)<1e-5);}
});
