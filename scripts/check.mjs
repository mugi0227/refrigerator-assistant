import {readdirSync,readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
for(const dir of ['public','scripts','tests'])for(const f of readdirSync(dir)){if(/\.(js|mjs)$/.test(f))execFileSync(process.execPath,['--check',`${dir}/${f}`],{stdio:'inherit'});}
JSON.parse(readFileSync('public/manifest.webmanifest','utf8'));JSON.parse(readFileSync('package.json','utf8'));
console.log('Syntax and manifests OK');
