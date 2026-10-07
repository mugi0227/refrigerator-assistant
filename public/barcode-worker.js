// Decode outside the rendering thread. Decoding does not send images anywhere.
let reader;
self.onmessage=async({data})=>{
  try {
    if(!reader) {
      const mod=await import('https://cdn.jsdelivr.net/npm/zxing-wasm@3.1.5/reader/+esm');
      mod.prepareZXingModule({overrides:{locateFile:(path,prefix)=>path.endsWith('.wasm')?'https://cdn.jsdelivr.net/npm/zxing-wasm@3.1.5/dist/reader/zxing_reader.wasm':prefix+path}});
      reader=mod.readBarcodes;
    }
    const pixels=new ImageData(new Uint8ClampedArray(data.buffer),data.width,data.height);
    const result=await reader(pixels,{formats:['EAN13','EAN8','UPCA','UPCE','QRCode','DataMatrix','Code128'],tryHarder:false,maxNumberOfSymbols:2});
    self.postMessage({id:data.id,codes:result.filter(r=>r.isValid!==false).map(r=>({text:r.text,format:r.format}))});
  } catch(error) {self.postMessage({id:data.id,error:error.message||String(error)});}
};
