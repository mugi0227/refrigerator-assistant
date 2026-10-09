// Run explicitly when changing the candidate vocabulary; never on deploy.
import {AutoTokenizer,SiglipTextModel,env} from '@huggingface/transformers';
import {mkdir,writeFile,copyFile} from 'node:fs/promises';
import {normalize} from '../public/siglip-core.js';
env.cacheDir='local/huggingface';
const model='onnx-community/siglip2-base-patch16-224-ONNX';
const revision='ba1f3b0843f24bc5417d38e19c37b287d719b2f4';
const foods=[['トマト','tomatoes'],['にんじん','carrots'],['キャベツ','cabbage'],['ブロッコリー','broccoli'],['ほうれん草','spinach'],['小松菜','komatsuna mustard spinach'],['きゅうり','cucumbers'],['玉ねぎ','onions'],['じゃがいも','potatoes'],['ピーマン','green bell peppers'],['パプリカ','red and yellow bell peppers'],['なす','eggplants'],['レタス','lettuce'],['大根','daikon radishes'],['白菜','napa cabbage'],['長ねぎ','Japanese long green onions'],['かぼちゃ','kabocha squash'],['さつまいも','sweet potatoes'],['もやし','bean sprouts'],['しめじ','shimeji mushrooms'],['しいたけ','shiitake mushrooms'],['えのき','enoki mushrooms'],['エリンギ','king oyster mushrooms'],['とうもろこし','corn on the cob'],['オクラ','okra'],['れんこん','lotus roots'],['ごぼう','burdock roots'],['にんにく','garlic'],['生姜','ginger roots'],['りんご','apples'],['バナナ','bananas'],['みかん','mandarin oranges'],['レモン','lemons'],['いちご','strawberries'],['キウイ','kiwi fruit']];
const negatives=[['対象外：包装された商品','packaged food with a printed label'],['対象外：料理','a cooked meal on a plate'],['対象外：空の背景','an empty kitchen counter'],['対象外：食品以外','household objects, not food'],['対象外：複数の種類','a mixture of different vegetables'],['対象外：肉・魚','raw meat or fish'],['対象外：卵・乳製品','eggs and dairy products']];
await mkdir('public/vendor/ort-1.30.0',{recursive:true});
for(const name of ['ort.wasm.min.mjs','ort-wasm-simd-threaded.mjs','ort-wasm-simd-threaded.wasm'])await copyFile(`node_modules/onnxruntime-web/dist/${name}`,`public/vendor/ort-1.30.0/${name}`);
const license=await fetch('https://raw.githubusercontent.com/microsoft/onnxruntime/v1.30.0/LICENSE');
if(!license.ok)throw new Error('Could not fetch runtime license');
await writeFile('public/vendor/ort-1.30.0/LICENSE.txt',await license.text());
for(const [path,url] of [['public/vendor/ort-1.30.0/ThirdPartyNotices.txt','https://raw.githubusercontent.com/microsoft/onnxruntime/v1.30.0/ThirdPartyNotices.txt'],['public/siglip-model-LICENSE.txt','https://www.apache.org/licenses/LICENSE-2.0.txt']]){
  const response=await fetch(url);if(!response.ok)throw new Error(`License HTTP ${response.status}`);
  await writeFile(path,await response.text());
}
const options={revision,dtype:'q8',device:'cpu'};
console.log('Loading pinned text encoder (development machine only)');
const tokenizer=await AutoTokenizer.from_pretrained(model,{revision});
const encoder=await SiglipTextModel.from_pretrained(model,options);
const labels=[];
for(const [label,description] of [...foods,...negatives]){
  const prompt=`this is a photo of ${description}.`;
  const inputs=tokenizer(prompt,{padding:'max_length',max_length:64,truncation:true});
  const output=await encoder(inputs);
  const vector=output.pooler_output??output.text_embeds;
  if(!vector||vector.data.length!==768)throw new Error(`Unexpected text output: ${Object.keys(output)}`);
  labels.push({label,food:!label.startsWith('対象外'),prompt,embedding:Array.from(normalize(vector.data),n=>Number(n.toFixed(8)))});
  console.log(label);
}
await writeFile('public/siglip-labels.json',JSON.stringify({model,revision,textDtype:'q8',dimensions:768,labels}));
await encoder.dispose();
console.log('Wrote candidate vectors and pinned WASM runtime');
