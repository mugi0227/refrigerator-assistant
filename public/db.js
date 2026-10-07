import {emptyState, createItem, consumePlan, cleanName} from './core.js';
const DB_NAME='refrigerator-assistant', STORE='home';
let connection;
export function openDB() {
  return connection ??= new Promise((resolve,reject)=>{
    const request=indexedDB.open(DB_NAME,1);
    request.onupgradeneeded=()=>request.result.createObjectStore(STORE);
    request.onsuccess=()=>resolve(request.result); request.onerror=()=>reject(request.error);
  });
}
export async function readState() {
  const db=await openDB(); return new Promise((resolve,reject)=>{
    const request=db.transaction(STORE).objectStore(STORE).get('state');
    request.onsuccess=()=>resolve(request.result||emptyState()); request.onerror=()=>reject(request.error);
  });
}
/** Every mutation reads the latest state within ONE read/write transaction. */
export async function mutate(fn) {
  const db=await openDB(); return new Promise((resolve,reject)=>{
    const tx=db.transaction(STORE,'readwrite'), store=tx.objectStore(STORE), req=store.get('state'); let result, error;
    req.onsuccess=()=>{ try {const state=req.result||emptyState(); result=fn(state); store.put(state,'state');} catch(e) {error=e;tx.abort();} };
    tx.oncomplete=()=>{if(typeof BroadcastChannel!=='undefined'){const c=new BroadcastChannel(DB_NAME);c.postMessage('changed');c.close();} resolve(result);};
    tx.onerror=tx.onabort=()=>reject(error||tx.error||new Error('保存できませんでした。ブラウザの空き容量を確認してください'));
  });
}
function record(state,kind,changes) {
  const event={id:crypto.randomUUID(),kind,at:new Date().toISOString(),changes,undone:false};
  state.events=[event,...state.events].slice(0,200); return event;
}
function cache(state,item) {
  if(item.barcode) state.productCache[item.barcode]={name:item.name,kind:item.kind,unit:item.unit};
}
export function addItem(input) {
  const item=createItem(input); return mutate(state=>{state.items.push(item);cache(state,item);return record(state,'add',[{before:null,after:{...item}}]);});
}
export function editItem(input) {
  return mutate(state=>{const i=state.items.findIndex(x=>x.id===input.id); if(i<0) throw new Error('在庫が見つかりません');
    const before={...state.items[i]}, after=createItem({...input,rev:before.rev+1}); state.items[i]=after;cache(state,after);return record(state,'edit',[{before,after}]);});
}
export function consume(candidate,quantity) {
  return mutate(state=>{const changes=consumePlan(state.items,candidate,quantity);for(const change of changes){state.items[state.items.findIndex(i=>i.id===change.after.id)]=change.after;}return record(state,'consume',changes);});
}
export function consumeExact(id,quantity) {
  return mutate(state=>{const i=state.items.findIndex(x=>x.id===id);if(i<0) throw new Error('在庫が見つかりません');
    const before={...state.items[i]}, q=Number(quantity);if(!Number.isFinite(q)||q<=0||q>before.quantity) throw new Error('消費量が在庫を超えています');
    const after={...before,quantity:Math.round((before.quantity-q)*1000)/1000,rev:before.rev+1};state.items[i]=after;return record(state,'consume',[{before,after}]);});
}
export function undo(eventId) {
  return mutate(state=>{const event=state.events.find(e=>e.id===eventId);if(!event||event.undone) throw new Error('この操作は取り消せません');
    for(const c of event.changes){const current=state.items.find(i=>i.id===c.after.id);if(!current||current.rev!==c.after.rev||JSON.stringify(current)!==JSON.stringify(c.after))throw new Error('その後に在庫が更新されています。個別に編集してください');}
    for(const c of event.changes){const i=state.items.findIndex(x=>x.id===c.after.id);if(c.before)state.items[i]={...c.before,rev:c.after.rev+1};else state.items.splice(i,1);}event.undone=true;
  });
}
export async function rememberProduct(barcode,name) {
  return mutate(s=>{s.productCache[barcode]={name:cleanName(name),kind:'packaged',unit:'個'};});
}
