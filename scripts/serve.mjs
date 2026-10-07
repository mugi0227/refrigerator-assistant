import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,extname,relative,isAbsolute} from 'node:path';
const root=resolve('public'),port=Number(process.env.PORT||4173);
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.webmanifest':'application/manifest+json'};
createServer(async(req,res)=>{try{const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);const file=resolve(root,'.'+(pathname==='/'?'/index.html':pathname));const relativeFile=relative(root,file);if(relativeFile==='..'||relativeFile.startsWith('../')||relativeFile.startsWith('..\\')||isAbsolute(relativeFile)){res.writeHead(403);res.end();return;}
  const body=await readFile(file);res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream','Cache-Control':'no-store','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp','X-Content-Type-Options':'nosniff'});res.end(body);
}catch{res.writeHead(404);res.end('Not found');}}).listen(port,'0.0.0.0',()=>console.log(`fridge. → http://localhost:${port}\nPhone camera requires HTTPS (deploy public/ to Cloudflare).`));
