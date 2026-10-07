import {mkdirSync,readdirSync,readFileSync,writeFileSync,copyFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..'),out=resolve(root,'ios/Fridge/Resources/Web');
mkdirSync(out,{recursive:true});
for(const name of readdirSync(resolve(root,'public'))){if(['_headers','sw.js','manifest.webmanifest','barcode-worker.js'].includes(name))continue;copyFileSync(resolve(root,'public',name),resolve(out,name));}
const index=resolve(out,'index.html');let html=readFileSync(index,'utf8');
html=html.replace('<video id="camera" playsinline muted autoplay></video>','<img id="camera" alt="背面カメラの映像">');
html=html.replace('<link rel="manifest" href="./manifest.webmanifest">','');
html=html.replace('<meta charset="UTF-8">','<meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="default-src \'self\' fridge:; script-src \'self\' fridge:; style-src \'self\' \'unsafe-inline\'; img-src \'self\' data: blob:; connect-src https://world.openfoodfacts.org; object-src \'none\'; base-uri \'self\'; form-action \'self\'">');
writeFileSync(index,html);
const css=resolve(out,'styles.css');writeFileSync(css,readFileSync(css,'utf8')+'\n#camera{width:100%;height:100%;object-fit:cover;}\n.app-shell{padding-top:env(safe-area-inset-top);}\n');
console.log('Prepared bundled iOS UI (native camera and AI; no model weights included)');
