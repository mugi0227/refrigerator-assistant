export const MODEL={id:'onnx-community/siglip2-base-patch16-224-ONNX',revision:'ba1f3b0843f24bc5417d38e19c37b287d719b2f4',file:'vision_model_quantized.onnx',bytes:94553333,cache:'fridge-siglip2-ba1f3b08-q8.onnx'};
export const MODEL_URL=`https://huggingface.co/${MODEL.id}/resolve/${MODEL.revision}/onnx/${MODEL.file}`;
export function normalize(values){
  const norm=Math.hypot(...values);
  if(!Number.isFinite(norm)||norm===0)throw new Error('特徴量が不正です');
  return Float32Array.from(values,x=>x/norm);
}
// SigLIP2 config: RGB, 224 x 224 bilinear resize, rescale 1/255, mean/std 0.5.
export function rgbaToTensor(rgba,size=224){
  if(rgba.length!==size*size*4)throw new Error('画像サイズが不正です');
  const area=size*size,out=new Float32Array(area*3);
  for(let i=0;i<area;i++)for(let channel=0;channel<3;channel++)out[channel*area+i]=rgba[i*4+channel]/127.5-1;
  return out;
}
export function rankCandidates(values,catalog){
  const vector=normalize(values);
  return catalog.map(({label,food,embedding})=>{
    if(embedding.length!==vector.length)throw new Error('モデルと候補の次元が一致しません');
    const unit=normalize(embedding);let score=0;
    for(let i=0;i<vector.length;i++)score+=vector[i]*unit[i];
    return {label,food,score};
  }).sort((a,b)=>b.score-a.score);
}
