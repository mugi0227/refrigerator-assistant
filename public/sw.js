const CACHE='fridge-shell-v5';
const SHELL=['./','./index.html','./styles.css','./app.js','./core.js','./db.js','./vision.js','./model-cache.js','./native-bridge.js','./scanner.js','./barcode-worker.js','./icon.svg','./manifest.webmanifest'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)));});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('fridge-shell-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',event=>{
  const url=new URL(event.request.url);
  // Never cache model streams, remote API data, uploads, or arbitrary origins.
  if(event.request.method!=='GET'||url.origin!==self.location.origin)return;
  const basename=url.pathname.split('/').pop();
  if(!['','index.html','styles.css','app.js','core.js','db.js','vision.js','model-cache.js','native-bridge.js','scanner.js','barcode-worker.js','icon.svg','manifest.webmanifest'].includes(basename))return;
  event.respondWith(fetch(event.request).then(response=>{if(response.ok){const copy=response.clone();event.waitUntil(caches.open(CACHE).then(c=>c.put(event.request,copy)));}return response;}).catch(async()=>{const cached=await caches.match(event.request);return cached||new Response('オフラインです。初回はオンラインで開いてください。',{status:503,headers:{'Content-Type':'text/plain;charset=utf-8'}});}));
});
