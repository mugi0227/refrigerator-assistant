import {readFileSync, existsSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const app = readFileSync(resolve(root, 'ios/Fridge/FridgeApp.swift'), 'utf8');
const project = readFileSync(resolve(root, 'ios/project.yml'), 'utf8');
if (!app.includes('NativeRootView()') || project.includes('Fridge/Resources/Web')) {
  throw new Error('iOS must use the native root without bundled Web resources');
}
if (!existsSync(resolve(root, 'ios/Fridge/Resources/Probe/apple.png'))) {
  throw new Error('Missing reference image for native AI startup validation');
}
console.log('Validated native SwiftUI app and reference image; no Web UI is bundled.');
