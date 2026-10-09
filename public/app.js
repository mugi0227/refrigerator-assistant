import {LOCATIONS,EXPIRY,PRODUCE,canonicalName,emoji,today,daysLeft,planDate,addDays,shoppingNeeds,emptyState,validateBackup,validateStaple} from './core.js';
import {readState,mutate,addItem,editItem,consume,consumeExact,undo} from './db.js';
import {GemmaVision,previousModelLoad} from './vision.js';
import {CameraScanner,Sounds} from './scanner.js';
import {isNative,NativeGemmaVision,NativeCameraScanner,nativeCall} from './native-bridge.js';
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let state=emptyState(),view='home',search='',mode='add',runtimeStatus='Gemmaはまだ読み込まれていません',scanState={},demo=false,demoTimer=null,toastTimer=null,recipeResults=null,recipeBusy=false,editContext=null;
const sounds=new Sounds();
let modelProgress=null,savedModel=false,additionalReadingOpen=false,aiHintShown=false;
let layout=(()=>{try{return localStorage.getItem('fridge-layout')==='list'?'list':'shelf';}catch{return 'shelf';}})();
let interruptedLoad=previousModelLoad();
const vision=new (isNative?NativeGemmaVision:GemmaVision)(status=>{runtimeStatus=status;const el=$('#runtime-status');if(el)el.textContent=status;$('#metric').textContent=isNative?'食品と印字をこの端末で読み取ります':status;if(isNative&&view==='settings'&&!vision.loading)queueMicrotask(renderSettings);},progress=>{modelProgress=progress;if(['cached','saved'].includes(progress.phase))savedModel=true;updateModelProgress();});
const scanner=new (isNative?NativeCameraScanner:CameraScanner)({video:$('#camera'),vision,sounds,getState:()=>state,onChange:s=>{scanState=s;renderScan();},onCommit:commitCandidate,
  onStatus:status=>{$('#camera-status').textContent=status;},onMetric:m=>{$('#metric').textContent=isNative?'食品と印字をこの端末で読み取ります':`Gemma 4 E2B · ${(m.ms/1000).toFixed(2)}秒 / 回`;$('#raw-output').textContent=m.text;}});
if(isNative)$('#metric').textContent='バーコードと印字をこの端末で読み取ります';
document.addEventListener('toggle',event=>{if(event.target.id==='additional-reading')additionalReadingOpen=event.target.open;},true);
function notify(text,eventId=null){clearTimeout(toastTimer);$('#toast').innerHTML=`<span>${esc(text)}</span>${eventId?`<button data-action="undo" data-id="${esc(eventId)}">元に戻す</button>`:''}`;$('#toast').hidden=false;toastTimer=setTimeout(()=>{$('#toast').hidden=true;},eventId?9000:6000);}
async function refresh(){state=await readState();sounds.enabled=state.settings.sound!==false;renderCurrent();}
function options(obj,current){return Object.entries(obj).map(([v,t])=>`<option value="${esc(v)}" ${v===current?'selected':''}>${esc(t)}</option>`).join('');}
const units=['個','本','パック','束','袋','g','ml'];
function daysText(item){const days=daysLeft(item.expiryDate);return days===null?'期限なし':days<0?`${-days}日過ぎ`:days===0?'今日まで':days===1?'明日まで':`あと${days}日`;}
function urgency(item){const days=daysLeft(item.expiryDate);return days===null?'unknown':days<0?'expired':days<=3?'soon':'';}
function amount(item){return `${item.quantity}${item.unit}`;}
function dateLabel(item){const prefix=item.expiryType==='estimate'?'目安':item.expiryType==='use_by'?'消費':item.expiryType==='best_before'?'賞味':'';
  return `<span class="date-chip ${urgency(item)}">${esc(prefix)} ${esc(daysText(item))}${item.expiryDate?` · ${esc(item.expiryDate.slice(5).replace('-','/'))}`:''}</span>`;
}
function guessKind(name){const canonical=canonicalName(name);return PRODUCE[canonical]?'produce':canonical==='卵'?'eggs':'packaged';}
// One shelf slot per item. The amount badge is hidden for a single unit so a full shelf stays calm.
function foodTile(item){return `<button class="food-tile ${urgency(item)}" data-action="open-item" data-id="${esc(item.id)}"><span class="tile-icon"><span aria-hidden="true">${emoji(item.name)}</span>${item.quantity===1?'':`<b>${esc(amount(item))}</b>`}</span><span class="tile-name">${esc(item.name)}</span><span class="tile-days">${esc(daysText(item))}</span></button>`;}
function compartment(location,items){return `<section class="compartment ${location}-room" aria-label="${LOCATIONS[location]}"><h2 class="compartment-label">${LOCATIONS[location]}<span>${items.length}</span></h2><div class="shelf-items">${items.map(foodTile).join('')}</div></section>`;}
function activeItems(){return state.items.filter(i=>i.quantity>0).sort((a,b)=>(a.expiryDate||'9999').localeCompare(b.expiryDate||'9999'));}
function renderHome(){const items=activeItems(),soon=items.filter(i=>['soon','expired'].includes(urgency(i))),at=place=>items.filter(i=>i.location===place);
  $('#view-home').innerHTML=`<div class="page-head"><h1>冷蔵庫<span class="count">${items.length}品</span></h1><div class="head-actions"><div class="segmented compact" role="group" aria-label="表示">${[['shelf','棚'],['list','リスト']].map(([v,t])=>`<button class="${layout===v?'active':''}" data-action="layout" data-layout="${v}" aria-pressed="${layout===v}">${t}</button>`).join('')}</div><button class="add-button" data-action="manual" aria-label="食品を追加">＋</button></div></div>
    ${soon.length?`<div class="soon-strip"><h2>期限が近い</h2><div class="soon-items">${soon.map(i=>`<button class="soon-chip ${urgency(i)}" data-action="open-item" data-id="${esc(i.id)}"><span aria-hidden="true">${emoji(i.name)}</span>${esc(i.name)}<small>${esc(daysText(i))}</small></button>`).join('')}</div></div>`:''}
    ${layout==='list'?`<label class="sr-only" for="food-search">食品を検索</label><input type="search" class="searchbox" id="food-search" placeholder="検索" value="${esc(search)}"><div class="food-list" id="inventory-list"></div>`
      :`<div class="fridge">${compartment('fridge',at('fridge'))}${compartment('freezer',at('freezer'))}</div><div class="pantry">${compartment('pantry',at('pantry'))}</div>`}
    ${items.length?'':`<div class="empty-hint"><p>まだ何も入っていません</p><div class="button-row"><button class="secondary" data-action="manual">手入力で追加</button><button class="secondary" data-action="view" data-view="scan">スキャン</button></div></div>`}`;
  renderItems();
}
function renderItems(){const box=$('#inventory-list');if(!box)return;const items=activeItems().filter(i=>i.name.toLowerCase().includes(search.toLowerCase()));
  box.innerHTML=items.map(i=>`<div class="list-row"><button class="row-main" data-action="open-item" data-id="${esc(i.id)}"><span class="row-icon" aria-hidden="true">${emoji(i.name)}</span><span class="row-copy"><strong>${esc(i.name)}</strong><small>${esc(amount(i))} · ${LOCATIONS[i.location]}${i.opened?' · 開封済み':''}</small></span>${dateLabel(i)}</button><button class="minus-button" data-action="consume-one" data-id="${esc(i.id)}" aria-label="${esc(i.name)}を${Math.min(1,i.quantity)}${esc(i.unit)}減らす">−</button></div>`).join('')||(items.length||!search?'':'<p class="muted-line">見つかりません</p>');
}
function openItem(id){const item=state.items.find(i=>i.id===id&&i.quantity>0),sheet=$('#item-sheet');if(!item){if(sheet.open)sheet.close();return;}
  $('#item-detail').innerHTML=`<button type="button" class="icon-button sheet-close" data-action="close-item" aria-label="閉じる">×</button><div class="item-hero"><span class="item-icon" aria-hidden="true">${emoji(item.name)}</span><h2 id="item-title">${esc(item.name)}</h2><p>${esc(amount(item))} · ${LOCATIONS[item.location]}${item.opened?' · 開封済み':''}</p>${dateLabel(item)}${item.notes?`<p class="item-notes">${esc(item.notes)}</p>`:''}</div>
    <div class="item-actions"><button data-action="consume-one" data-id="${esc(item.id)}"><strong>−${Math.min(1,item.quantity)}</strong>減らす</button><button data-action="add-one" data-id="${esc(item.id)}"><strong>＋1</strong>増やす</button><button data-action="consume-all" data-id="${esc(item.id)}"><strong>✓</strong>使い切り</button></div><button class="secondary wide" data-action="edit-item" data-id="${esc(item.id)}">編集</button>`;
  if(!sheet.open)sheet.showModal();
}
function renderScan(){const s=scanState,target=s.pending||s.target,box=$('#scan-result');if(!box)return;
  if(!target){if(s.lock){box.hidden=false;box.innerHTML=`<div class="result-main"><div class="food-icon">✓</div><div><h3>${esc(s.lock.name)}</h3><p>${esc(s.message||'次の食品を映してください')}</p></div></div><div class="result-actions"><button data-action="next-same">同じ商品の次の1個</button><button class="cancel-link" data-action="manual">手入力</button></div>`;}else{box.hidden=true;$('#scan-subtitle').textContent=s.message||'枠の中に、食品を1種類ずつ';}return;}
  box.hidden=false;const pending=!!s.pending,remaining=pending?Math.max(0,Math.ceil((s.pending.deadline-Date.now())/1000)):0;
  const action=mode==='consume'?'消費':'登録';
  box.innerHTML=`<div class="result-main"><div class="food-icon">${emoji(target.name)}</div><div><h3>${esc(target.name)} ${target.quantity?`× ${esc(target.quantity)}`:''}</h3><p>${target.expiry?`${EXPIRY[target.expiry.type]} ${esc(target.expiry.date)}`:target.kind==='produce'?'使い切り目安を自動設定（調整できます）':target.printedDate?`${esc(target.printedDate.date)} · 賞味・消費の種類を確認してください`:esc(s.message||'賞味期限・消費期限の印字を映してください')}</p></div></div><div class="result-actions"><span class="fine-print" style="margin:0">${pending?`${remaining}秒後に${action}`:'食品を検知しています'}</span><div><button data-action="edit-scan">${target.printedDate?'期限を確認':'編集'}</button> <button class="cancel-link" data-action="cancel-scan">取消</button></div></div>${pending?'<div class="countdown"><div id="countdown-bar" style="width:100%"></div></div>':''}`;
  if(target.barcode){const detail=document.createElement('p');detail.className='fine-print';detail.style.margin='4px 0 0';detail.textContent='バーコード '+target.barcode;box.querySelector('.result-main>div:last-child').append(detail);}
}
setInterval(()=>{if(scanState.pending){const remaining=scanner.paused?5:Math.max(0,Math.ceil((scanState.pending.deadline-Date.now())/1000));const bar=$('#countdown-bar');if(bar)bar.style.width=`${Math.min(100,remaining/5*100)}%`;const label=$('#scan-result .result-actions>.fine-print');if(label)label.textContent=scanner.paused?'一時停止中':`${remaining}秒後に${mode==='consume'?'消費':'登録'}`;}},100);
function candidateInput(candidate){const produce=candidate.kind==='produce';return {...candidate,quantity:candidate.quantity||1,location:candidate.location||scanner.machine.location,expiryType:produce?'estimate':candidate.expiry?.type||'unknown',expiryDate:produce?planDate(candidate.name,1,today(),state.settings.shelfDays):candidate.expiry?.date||candidate.printedDate?.date||null,freshness:1,source:'camera'};}
async function commitCandidate(candidate){
  if(demo){sounds.play('registered');notify(`デモ：${candidate.name}を${candidate.mode==='consume'?'消費':'登録'}しました（保存なし）`);return;}
  try{const input=candidateInput(candidate);const event=candidate.mode==='consume'?await consume(input,input.quantity):await addItem(input);sounds.play('registered');notify(`${input.name}を${candidate.mode==='consume'?'消費':'登録'}しました`,event.id);await refresh();}
  catch(error){sounds.play('error');scanner.setPaused(true);$('#pause-scan').textContent='再開';notify(error.message);openEditor({...candidateInput(candidate),id:null},candidate.mode==='consume'?'scan-consume':'scan-add');}
}
async function navigate(next){if(!['home','scan','shopping','recipes','settings'].includes(next))next='home';
  if(view==='scan'&&next!=='scan'){endDemo();await scanner.stop();cameraUI(false);}view=next;
  $$('.view').forEach(el=>el.hidden=el.id!==`view-${view}`);$$('.bottom-nav button').forEach(btn=>{btn.classList.toggle('active',btn.dataset.view===view);btn.setAttribute('aria-current',btn.dataset.view===view?'page':'false');});
  if(location.hash!==`#${next}`)history.replaceState(null,'',`#${next}`);renderCurrent();window.scrollTo({top:0,behavior:'instant'});
}
function renderCurrent(){if(view==='home')renderHome();if(view==='settings')renderSettings();if(view==='shopping')renderShopping();if(view==='recipes')renderRecipes();}
function cameraUI(running){$('#camera-idle').hidden=running;$('#scan-frame').hidden=!running;$('#scan-subtitle').hidden=!running;$('#camera-stop').hidden=!running;$('#pause-scan').hidden=!running;$('#pause-scan').textContent='一時停止';}
async function startCamera(){endDemo();cameraUI(false);try{$('[data-action="camera-start"]').disabled=true;await scanner.start(mode,$('#scan-location').value);cameraUI(scanner.running);if(!vision.ready&&!isNative&&!aiHintShown){aiHintShown=true;notify('野菜・期限のAI認識には、設定からGemmaを読み込んでください');}}catch(error){await scanner.stop();cameraUI(false);notify(error.name==='NotAllowedError'?'カメラが許可されていません。Safariのサイト設定を確認してください。':error.message);}finally{$('[data-action="camera-start"]').disabled=false;}}
function startDemo(){navigate('scan');scanner.stop();demo=true;scanner.paused=false;sounds.unlock();scanner.machine.mode=mode;scanner.machine.location='fridge';scanner.machine.reset();cameraUI(true);$('#demo-banner').hidden=false;$('#demo-controls').hidden=false;$('#camera-status').textContent='操作デモ · 実物認識なし';$('#metric').textContent='デモ（AIは実行していません）';demoTimer=setInterval(()=>{if(!scanner.paused)scanner.machine.tick();},100);notify('「牛乳を映す」→「期限を映す」で自動登録の流れを試せます');}
function endDemo(){demo=false;clearInterval(demoTimer);demoTimer=null;$('#demo-banner').hidden=true;$('#demo-controls').hidden=true;}
function demoObserve(kind){if(!demo)return;const m=scanner.machine,now=Date.now();
  const milk={kind:'packaged',name:'牛乳',count:1,targetMatches:true,multiple:false,uncertain:false,expiry:null};
  if(kind==='milk')m.observe(milk,now);
  if(kind==='date'){const date=addDays(today(),5);const obs={...milk,expiry:{type:'best_before',date,raw:date,label:'賞味期限'}};m.observe(obs,now);m.observe(obs,now+100);}
  if(kind==='tomato'){const obs={kind:'produce',name:'トマト',count:3,targetMatches:false,multiple:false,uncertain:false,expiry:null};m.observe(obs,now);m.observe(obs,now+100);}
  if(kind==='empty'){m.observe({kind:'none'},now-1500);m.observe({kind:'none'},now);}
}
const PRESETS=[['牛乳',1,'本'],['卵',10,'個'],['ヨーグルト',1,'個'],['豆腐',1,'パック'],['納豆',3,'パック'],['チーズ',1,'個'],['ハム',1,'パック'],['豚肉',1,'パック'],['鶏肉',1,'パック'],['鮭',1,'パック'],['トマト',3,'個'],['キャベツ',1,'個'],['玉ねぎ',3,'個'],['にんじん',3,'本'],['きゅうり',3,'本'],['レタス',1,'個'],['もやし',1,'袋'],['きのこ',1,'パック'],['バナナ',3,'本'],['りんご',2,'個']];
// Recently stocked foods first (including used-up ones, the usual re-buys), then common staples.
function presets(){const seen=new Set(),list=[];
  for(const i of [...state.items].sort((a,b)=>(b.addedOn||'').localeCompare(a.addedOn||''))){const key=canonicalName(i.name);if(list.length>=8||seen.has(key)||i.name.startsWith('未登録'))continue;seen.add(key);list.push({name:i.name,quantity:PRESETS.find(p=>canonicalName(p[0])===key)?.[1]||1,unit:i.unit,kind:i.kind,location:i.location});}
  for(const [name,quantity,unit] of PRESETS)if(!seen.has(canonicalName(name))){seen.add(canonicalName(name));list.push({name,quantity,unit});}
  return list;
}
function choices(name,obj,current){return `<div class="choice">${Object.entries(obj).map(([v,t])=>`<label><input type="radio" name="${name}" value="${esc(v)}" ${v===current?'checked':''}><span>${esc(t)}</span></label>`).join('')}</div>`;}
function openEditor(item={},context='add',extra={}){
  if(demo){notify('デモ中は保存しません。カメラを終了すると手入力できます');return;}
  scanner.setPaused(true);if(context.startsWith('scan'))scanner.machine.cancel();editContext={context,item,presets:context==='add'?presets():[],...extra};
  const current={name:'',quantity:1,unit:'個',kind:'packaged',location:state.settings.location||'fridge',expiryType:'unknown',expiryDate:'',freshness:1,...item};
  const consuming=context==='scan-consume',editing=context==='edit';
  $('#editor-form').innerHTML=`<div class="dialog-heading"><h2 id="editor-title">${consuming?'消費する量':editing?'編集':'食品を追加'}</h2><button type="button" class="icon-button" data-action="close-editor" aria-label="閉じる">×</button></div>
    ${editContext.presets.length?`<div class="preset-grid" role="group" aria-label="よく使う食品">${editContext.presets.map((p,index)=>`<button type="button" class="preset" data-action="preset" data-index="${index}"><span aria-hidden="true">${emoji(p.name)}</span>${esc(p.name)}</button>`).join('')}</div>`:''}
    <div class="editor-name"><span class="editor-icon" id="editor-icon" aria-hidden="true">${emoji(current.name)}</span><label>食品名<input name="name" value="${esc(current.name)}" required maxlength="80" placeholder="例：牛乳" autocomplete="off"></label></div>
    <div class="field"><span class="field-label">${consuming?'消費する数量':'数量'}</span><div class="quantity-row"><div class="stepper"><button type="button" data-action="step" data-step="-1" aria-label="1減らす">−</button><input name="quantity" type="number" inputmode="decimal" step="0.001" min="0.001" max="100000" value="${esc(current.quantity)}" required aria-label="数量"><button type="button" data-action="step" data-step="1" aria-label="1増やす">＋</button></div><select name="unit" aria-label="単位">${units.map(u=>`<option ${u===current.unit?'selected':''}>${u}</option>`).join('')}</select></div></div>
    <div class="field"><span class="field-label">保存場所</span>${choices('location',LOCATIONS,current.location)}</div>
    <div id="expiry-fields" ${consuming?'hidden':''}><div class="field"><span class="field-label">期限</span>${choices('expiryType',{best_before:'賞味',use_by:'消費',estimate:'目安',unknown:'なし'},current.expiryType)}
      <div class="date-row"><input name="expiryDate" type="date" value="${esc(current.expiryDate||'')}" aria-label="期限の日付"><div class="date-chips">${[[3,'3日後'],[7,'1週間'],[14,'2週間'],[30,'1か月']].map(([d,t])=>`<button type="button" data-action="date-chip" data-days="${d}">${t}</button>`).join('')}</div></div></div>
      <div id="freshness-fields" class="field" ${current.kind==='produce'?'':'hidden'}><span class="field-label">状態</span><input name="freshness" type="range" min="0" max="2" step="1" value="${current.freshness}" aria-label="状態"><span class="range-labels"><span>早めに使う</span><span>普通</span><span>新鮮</span></span><p class="fine-print">目安日は自分で選んだ状態から計算する計画用の日付です。安全性は判定しません。</p></div>
      <details class="more"><summary>詳細</summary><label>種類<select name="kind">${options({packaged:'パッケージ商品',produce:'野菜・果物',eggs:'卵'},current.kind)}</select></label><label class="checkbox-label"><input name="opened" type="checkbox" ${current.opened?'checked':''}>開封済み（印字の期限は未開封時のもの）</label><label>メモ<input name="notes" maxlength="80" value="${esc(current.notes||'')}" placeholder="保存方法・開封日など"></label>${current.barcode?`<p class="fine-print">商品コード ${esc(current.barcode)}</p>`:''}</details></div>
    ${consuming?'<p class="notice">同じ食品・単位・保存場所の在庫を、期限の近いものから減らします。</p>':''}<p id="editor-error" class="form-error" role="alert"></p><div class="sheet-footer"><button class="primary" type="submit">${consuming?'消費を記録':editing?'変更を保存':'追加する'}</button></div>`;
  if(context==='add'&&current.name&&!item.kind)syncEditor($('#editor-form'),'name');
  $('#editor').showModal();
}
// Keep kind, expiry type and date consistent while the person edits, so fewer fields need touching.
function syncEditor(form,changed){const f=form.elements;$('#editor-icon').textContent=emoji(f.name.value);
  if(changed==='name'&&editContext.context==='add'){f.kind.value=guessKind(f.name.value);if(f.kind.value==='produce'&&f.expiryType.value==='unknown')f.expiryType.value='estimate';if(f.kind.value!=='produce'&&f.expiryType.value==='estimate'){f.expiryType.value='unknown';f.expiryDate.value='';}}
  if(changed==='kind'&&f.kind.value==='produce')f.expiryType.value='estimate';
  if(changed==='expiryDate'&&f.expiryDate.value&&f.expiryType.value==='unknown')f.expiryType.value=f.kind.value==='produce'?'estimate':'best_before';
  $('#freshness-fields').hidden=f.kind.value!=='produce';
  if(f.expiryType.value==='unknown')f.expiryDate.value='';
  if(f.expiryType.value==='estimate'&&['freshness','kind','expiryType','name'].includes(changed))f.expiryDate.value=planDate(f.name.value,Number(f.freshness.value),today(),state.settings.shelfDays);
}
function closeEditor(){$('#editor').close();}
$('#editor-form').addEventListener('submit',async event=>{event.preventDefault();const button=event.submitter;button.disabled=true;
  try{const fields=Object.fromEntries(new FormData(event.currentTarget));const input={...editContext.item,...fields,quantity:Number(fields.quantity),freshness:Number(fields.freshness??1),opened:fields.opened==='on',source:editContext.context.startsWith('scan')?'camera':'manual'};
    let result;if(editContext.context==='scan-consume')result=await consume(input,input.quantity);else if(editContext.context==='edit')result=await editItem(input);else result=await addItem({...input,id:undefined});
    if(editContext.shoppingId)await mutate(s=>{const memo=s.shopping.find(i=>i.id===editContext.shoppingId);if(memo)memo.done=true;});
    sounds.play('registered');closeEditor();notify(`${input.name}を${editContext.context==='scan-consume'?'消費しました':editContext.context==='edit'?'保存しました':'追加しました'}`,result.id);await refresh();
  }catch(error){$('#editor-error').textContent=error.message;}finally{button.disabled=false;}
});
$('#editor-form').addEventListener('input',event=>{if(event.target.name==='name')$('#editor-icon').textContent=emoji(event.target.value);});
$('#editor-form').addEventListener('change',event=>syncEditor(event.currentTarget,event.target.name));
$('#editor').addEventListener('close',()=>scanner.setPaused(false));
// Tapping the dimmed area closes a sheet; the dialog element itself is only hit outside its padded content.
for(const dialog of $$('dialog'))dialog.addEventListener('click',event=>{if(event.target===dialog)dialog.close();});
function renderShopping(){const needs=shoppingNeeds(state),row=(icon,body,actions)=>`<div class="shopping-row">${icon}<div class="row-copy">${body}</div>${actions}</div>`;
  $('#view-shopping').innerHTML=`<div class="page-head"><h1>買い物</h1><button class="small-button" data-action="add-staple">＋ 常備品</button></div>
    <form id="shopping-form" class="inline-form"><label class="sr-only" for="shopping-name">買うもの</label><input id="shopping-name" name="name" required maxlength="80" placeholder="買うものを追加"><button class="primary" type="submit">追加</button></form>
    ${needs.length?`<h2 class="section-title">補充が必要<span class="count">${needs.length}</span></h2>${needs.map(n=>row(`<span class="row-icon" aria-hidden="true">${emoji(n.name)}</span>`,`<strong>${esc(n.name)}</strong><small>あと${n.buy}${esc(n.unit)}（いま${n.have}${esc(n.unit)}）</small>`,`<button class="small-button" data-action="stock" data-name="${esc(n.name)}" data-quantity="${n.buy}" data-unit="${esc(n.unit)}">買った</button>`)).join('')}`:''}
    <h2 class="section-title">メモ</h2>${state.shopping.map(s=>`<div class="shopping-row ${s.done?'done':''}"><input type="checkbox" data-shopping-id="${esc(s.id)}" ${s.done?'checked':''} aria-label="${esc(s.name)} 購入済み"><span class="row-icon" aria-hidden="true">${emoji(s.name)}</span><div class="row-copy"><strong>${esc(s.name)}</strong></div>${s.done?'':`<button class="small-button" data-action="stock" data-name="${esc(s.name)}" data-shopping="${esc(s.id)}">買った</button>`}<button class="icon-button" data-action="remove-shopping" data-id="${esc(s.id)}" aria-label="${esc(s.name)}を削除">×</button></div>`).join('')||'<p class="muted-line">メモはありません</p>'}
    <h2 class="section-title">常備品</h2><p class="muted-line">数量が補充ラインを下回ると「補充が必要」に出ます。</p>${state.staples.map(s=>row(`<span class="row-icon" aria-hidden="true">${emoji(s.name)}</span>`,`<strong>${esc(s.name)}</strong><small>${s.minimum}${esc(s.unit)}未満で補充 → ${s.target}${esc(s.unit)}まで</small>`,`<button class="icon-button" data-action="remove-staple" data-id="${esc(s.id)}" aria-label="${esc(s.name)}の常備設定を削除">×</button>`)).join('')}`;
  $('#shopping-form').onsubmit=async e=>{e.preventDefault();const name=e.currentTarget.elements.name.value.trim();if(!name)return;await mutate(s=>s.shopping.push({id:crypto.randomUUID(),name,done:false}));await refresh();$('#shopping-name')?.focus();};
}
$('#staple-form').addEventListener('submit',async e=>{e.preventDefault();const form=e.currentTarget;try{const staple=validateStaple(Object.fromEntries(new FormData(form)));await mutate(s=>{if(s.staples.some(x=>canonicalName(x.name)===canonicalName(staple.name)&&x.unit===staple.unit))throw new Error('この常備品は登録済みです');s.staples.push(staple);});$('#staple-editor').close();form.reset();notify('常備品に追加しました');await refresh();}catch(error){$('#staple-error').textContent=error.message;}});
function renderRecipes(){const items=activeItems(),eligible=items.filter(i=>daysLeft(i.expiryDate)===null||daysLeft(i.expiryDate)>=0);$('#view-recipes').innerHTML=`<div class="page-head"><h1>献立</h1></div>${!vision.ready?'<div class="notice">献立の提案には端末内AI（Gemma）を使います。<button class="text-button" data-action="view" data-view="settings">設定で準備 →</button></div>':''}
    <div class="recipe-start"><p>使える食材${eligible.length}品から、3つの献立を提案します。</p><button class="primary" data-action="generate-recipes" ${recipeBusy||!eligible.length?'disabled':''}>${recipeBusy?'考えています…':'献立を提案'}</button></div>
    <div class="recipe-tags">${eligible.map(i=>`<span>${emoji(i.name)} ${esc(i.name)} ${esc(i.quantity)}${esc(i.unit)}</span>`).join('')||'<p class="muted-line">まず食品を登録してください。</p>'}</div>
    ${recipeResults?recipeResults.map((r,index)=>`<article class="recipe-card"><div class="recipe-number">${index+1}</div><h3>${esc(r.name)}</h3><div class="recipe-tags">${r.ingredients.map(i=>`<span>${esc(i)}</span>`).join('')}</div><p style="margin-top:12px">買い足し・要確認：${r.missing.map(esc).join('、')||'なし（調味料の在庫もご確認ください）'}</p><ol>${r.steps.map(step=>`<li>${esc(step)}</li>`).join('')}</ol></article>`).join(''):''}
    <p class="fine-print">期限・使い切り目安を過ぎた食材は除外しています。AIの提案は安全性や栄養を保証しません。食材の状態、保存条件、アレルギーを確認してください。</p>`;
}
async function generateRecipes(){if(!vision.ready){notify('設定からGemmaを読み込んでください');return;}if(vision.busy){notify('カメラのAI処理が終わってからお試しください');return;}recipeBusy=true;renderRecipes();try{const items=activeItems().filter(i=>daysLeft(i.expiryDate)===null||daysLeft(i.expiryDate)>=0);recipeResults=await vision.recipes(items);}catch(error){notify(error.message);}finally{recipeBusy=false;if(view==='recipes')renderRecipes();}}
function updateModelProgress(){const box=$('#model-progress');if(!box)return;const p=modelProgress;box.hidden=!p;if(!p)return;
  const labels={checking:'1 / 3 · 保存モデルを確認',downloading:'1 / 3 · モデルをダウンロード',saving:'1 / 3 · 端末への保存を完了中',saved:'1 / 3 · 端末に保存しました',cached:'1 / 3 · 保存済みモデルを使用',runtime:'2 / 3 · 実行環境を準備',initializing:'3 / 3 · AIを起動',checkingImage:'3 / 3 · 画像読み取りを確認',ready:'準備完了',error:'読み込みに失敗しました',cancelled:'ダウンロードを中止しました'};
  $('#model-phase').textContent=labels[p.phase]||'モデルを読み込み中';const bar=$('#model-bar');
  bar.hidden=['error','cancelled'].includes(p.phase);
  const determinate=['downloading','saving','saved','cached','ready'].includes(p.phase);bar.max=p.total||1;if(determinate)bar.value=p.phase==='ready'?bar.max:p.loaded;else bar.removeAttribute('value');
  const elapsed=Math.max(0,Math.floor((performance.now()-vision.started)/1000));const bytes=p.total?`${(p.loaded/1e6).toFixed(0)} / ${(p.total/1e6).toFixed(0)} MB` :'';
  $('#model-progress-detail').textContent=p.phase==='downloading'?`${Math.floor(p.loaded/p.total*100)}% · ${bytes} · ${elapsed}秒`:p.phase==='initializing'?`ダウンロード完了。起動の残り時間は測れません · ${elapsed}秒` :p.phase==='ready'?'カメラで食品を読み取れます':`経過 ${elapsed}秒`;
  $('#model-cancel').hidden=!(vision.loading&&p.phase==='downloading');
  const cache=$('#model-cache-status');if(cache)cache.textContent=savedModel?'モデル：端末に保存済み':'モデル：端末には未保存';
}
function renderSettings(){const capable=isNative||!!navigator.gpu;$('#view-settings').innerHTML=`<div class="page-head"><h1>設定</h1><span class="date-chip">v${esc(globalThis.fridgeAppVersion||'0.1')}</span></div>
    ${isNative?`<div class="settings-card"><h2>カメラで読み取る</h2><p>商品のバーコードを映したあと、同じ商品の期限の印字を映してください。日付だけ読めた場合は、期限の種類を確認して登録できます。</p><p class="fine-print">この読み取りに追加のダウンロードは必要ありません。</p></div><details class="settings-card" id="additional-reading" ${additionalReadingOpen?'open':''}><summary>野菜の読み取り・献立の準備（任意）</summary>`:''}<div class="settings-card"><h2>端末内AI（Gemma 4 E2B）</h2><p>${isNative?'約2.6GB':'約2GB'}のモデルをこの端末に保存し、食品を読み取ります。保存済みなら再ダウンロードを省けます。AIの起動はページを開くたびに必要です。</p>${interruptedLoad?`<div class="notice amber">前回は${esc(({downloading:'ダウンロード',initializing:'AIの起動',runtime:'実行環境の準備'})[interruptedLoad.phase]||'読み込み')}の途中でページが閉じられました。${isNative?'アプリが途中で閉じられた場合は、端末のメモリ不足が考えられます。':'Safariが白い画面になって戻る場合は、端末のメモリ不足が考えられます。'}${savedModel?'モデルは保存済みなので、再ダウンロードは不要です。':'ダウンロードが完了していなければ、再取得が必要です。'}</div>`:''}<div class="runtime-status" id="runtime-status">${esc(runtimeStatus)}</div><div class="model-progress" id="model-progress" hidden><div class="model-progress-heading"><strong id="model-phase"></strong></div><progress id="model-bar" aria-label="モデルのダウンロードと起動の進行状況" max="1"></progress><p id="model-progress-detail"></p><button class="secondary" data-action="cancel-model" id="model-cancel" hidden>ダウンロードを中止</button></div><p><span id="model-cache-status">${savedModel?'モデル：端末に保存済み':'モデル：端末には未保存'}</span><br>${isNative?'AI実行：iOSネイティブ（文章：GPU / 画像：CPU）':'WebGPU：'+(capable?'検出しました（起動できるかは端末のメモリにも依存します）':'利用できません。手動登録は使えます。')}</p><div class="button-row"><button class="primary" data-action="load-model" ${vision.loading||vision.busy||vision.ready||!capable?'disabled':''}>${vision.ready?'✓ AI準備完了':vision.loading?'読み込み中…':savedModel?'保存したモデルで起動':'モデルを保存して起動'}</button><button class="secondary" data-action="model-file" ${vision.loading||vision.busy||!capable?'disabled':''}>ファイルから</button><button class="text-button" data-action="unload-model" ${!vision.ready||vision.busy?'disabled':''}>メモリを解放</button></div><p class="fine-print">Wi-Fiと充電につなぎ、この画面を開いたままお待ちください。${isNative?'アプリのデータを削除すると、モデルの再取得が必要です。':'サイトデータの削除やSafariの容量整理でモデルが消えた場合は再取得が必要です。'}保存しても起動時のメモリ不足は解消できないことがあります。ダウンロード元：Hugging Face / 実行環境：Google LiteRT-LM。</p></div>${isNative?'</details>':''}
    <div class="settings-card"><h2>読み取りと保存</h2><label class="setting-row"><span>検知音・登録音<small>映像を見ずに、完了がわかる</small></span><input type="checkbox" data-setting="sound" ${state.settings.sound?'checked':''}></label><label class="setting-row"><span>野菜の読み取り間隔<small>毎回の推論終了後に待つ時間</small></span><select data-setting="interval">${options({'600':'短め · 0.6秒','1200':'標準 · 1.2秒','2500':'ゆったり · 2.5秒'},String(state.settings.interval||1200))}</select></label><label class="setting-row"><span>最初の保存場所</span><select data-setting="location">${options(LOCATIONS,state.settings.location)}</select></label><label class="setting-row"><span>バーコードから商品名を探す<small>Open Food Factsへバーコードの番号だけを送信。<br>未収録の日本の商品もあります。画像は送りません。</small></span><input type="checkbox" data-setting="externalLookup" ${state.settings.externalLookup?'checked':''}></label></div>
    <div class="settings-card"><h2>野菜の使い切り目安</h2><p>「普通」の状態で、何日後に使い切りを促すか。試作用の初期値です。保存期間や安全性を保証する基準ではありません。変更は今後の登録に適用します。</p><div class="shelf-grid">${Object.entries(PRODUCE).map(([name,v])=>`<label>${v.emoji} ${name}<span><input type="number" min="1" max="60" value="${state.settings.shelfDays?.[name]||v.days}" data-shelf="${name}" aria-label="${name}の使い切り目安（日）"> 日</span></label>`).join('')}</div></div>
    <div class="settings-card"><h2>データとバックアップ</h2><p>${isNative?'在庫はこのアプリの中に保存されます。アプリを削除すると消えるため、バックアップをご利用ください。':'在庫はこのブラウザのIndexedDBに保存されます。サイトデータの削除で消えるため、バックアップをご利用ください。'}端末間の自動同期・バックグラウンド期限通知はありません。</p><div class="button-row"><button class="secondary" data-action="export">書き出す</button><button class="secondary" data-action="import">読み込む</button><button class="text-button" data-action="demo-start">操作デモ</button></div></div>
    <div class="settings-card"><h2>最近の操作</h2>${state.events.slice(0,12).map(e=>`<div class="history-row"><p>${esc(({add:'追加',edit:'編集',consume:'消費'})[e.kind]||e.kind)}：${esc(e.changes[0]?.after.name)}${e.undone?'（取消済み）':''}</p><time>${new Date(e.at).toLocaleTimeString('ja-JP',{hour:'2-digit',minute:'2-digit'})}</time>${!e.undone?`<button data-action="undo" data-id="${esc(e.id)}">取消</button>`:''}</div>`).join('')||'<p>まだ操作はありません。</p>'}</div>
    <p class="fine-print">このアプリは食品の安全性を判定しません。カビ・異臭など気になる点がある食品は、目安に関係なく使用を控えてください。読み取った日付は編集・取消できます。</p>`;updateModelProgress();
}
async function loadModel(file){let ticker;try{const loading=vision.load(file);if(view==='settings')renderSettings();ticker=setInterval(updateModelProgress,1000);await loading;interruptedLoad=null;notify('Gemmaの準備ができました。カメラでお試しください');}catch(error){runtimeStatus=error.name==='AbortError'?'ダウンロードを中止しました':error.message;notify(runtimeStatus.split('\n')[0]);}finally{clearInterval(ticker);if(view==='settings')renderSettings();}}
function exportData(){if(isNative){nativeCall('shareBackup',{json:JSON.stringify(state)}).catch(error=>notify(error.message));return;}const blob=new Blob([JSON.stringify(state,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`fridge-backup-${today()}.json`;a.click();setTimeout(()=>URL.revokeObjectURL(url),30000);notify('バックアップを書き出しました');}
$('#backup-file').onchange=async event=>{try{const file=event.target.files[0];if(!file)return;if(file.size>5*1024*1024)throw new Error('5MB以下のバックアップを選択してください');const data=validateBackup(JSON.parse(await file.text()));if(!confirm(`現在の在庫を、バックアップ内の${data.items.length}件に置き換えます。続けますか？`))return;await mutate(s=>{for(const k of Object.keys(s))delete s[k];Object.assign(s,data);});await refresh();notify('バックアップを読み込みました');}catch(error){notify(error.message);}finally{event.target.value='';}};
$('#model-file').onchange=async event=>{const file=event.target.files[0];if(file)await loadModel(file);event.target.value='';};
$('#scan-location').onchange=async event=>{scanner.machine.cancel();scanner.machine.location=event.target.value;notify(`${LOCATIONS[event.target.value]}の食品を読み取ります`);};
document.addEventListener('input',event=>{if(event.target.id==='food-search'){search=event.target.value;renderItems();}});
document.addEventListener('change',async event=>{const el=event.target;try{if(el.dataset.setting){const key=el.dataset.setting;await mutate(s=>s.settings[key]=el.type==='checkbox'?el.checked:key==='interval'?Number(el.value):el.value);state=await readState();sounds.enabled=state.settings.sound;if(key==='location')$('#scan-location').value=state.settings.location;}
  if(el.dataset.shelf){const n=Number(el.value);if(!Number.isInteger(n)||n<1||n>60)throw new Error('目安は1〜60日で設定してください');await mutate(s=>{s.settings.shelfDays??={};s.settings.shelfDays[el.dataset.shelf]=n;});state=await readState();}
  if(el.dataset.shoppingId){await mutate(s=>{const item=s.shopping.find(i=>i.id===el.dataset.shoppingId);if(item)item.done=el.checked;});await refresh();}
}catch(error){notify(error.message);}});
document.addEventListener('click',async event=>{const button=event.target.closest('[data-action]');if(!button)return;const a=button.dataset.action,id=button.dataset.id;
  try{
    // Opening the scan tab is already the intent to scan, so start the camera without another tap.
    if(a==='view'){await navigate(button.dataset.view);if(view==='scan'&&!scanner.running&&!demo)await startCamera();}
    if(a==='layout'){layout=button.dataset.layout;try{localStorage.setItem('fridge-layout',layout);}catch{/* per-device convenience only */}renderHome();}
    if(a==='manual')openEditor();
    if(a==='open-item')openItem(id);
    if(a==='close-item')$('#item-sheet').close();
    if(a==='edit-item'){const item=state.items.find(i=>i.id===id);$('#item-sheet').close();if(item)openEditor(item,'edit');}
    if(a==='add-one'){const item=state.items.find(i=>i.id===id);if(item){const result=await editItem({...item,quantity:Math.round((item.quantity+1)*1000)/1000});$('#item-sheet').close();notify(`${item.name}を1${item.unit}増やしました`,result.id);await refresh();}}
    if(a==='stock')openEditor({name:button.dataset.name,quantity:Number(button.dataset.quantity)||1,unit:button.dataset.unit||'個'},'add',{shoppingId:button.dataset.shopping});
    if(a==='preset'){const p=editContext?.presets[Number(button.dataset.index)],form=$('#editor-form');if(p){const f=form.elements;f.name.value=p.name;f.quantity.value=p.quantity;f.unit.value=p.unit;if(p.location)f.location.value=p.location;syncEditor(form,'name');if(p.kind){f.kind.value=p.kind;syncEditor(form,'kind');}$$('.preset').forEach(b=>b.classList.toggle('active',b===button));}}
    if(a==='step'){const q=$('#editor-form').elements.quantity,next=Math.round(((Number(q.value)||0)+Number(button.dataset.step))*1000)/1000;if(next>0)q.value=next;}
    if(a==='date-chip'){const form=$('#editor-form');form.elements.expiryDate.value=addDays(today(),Number(button.dataset.days));syncEditor(form,'expiryDate');}
    if(a==='consume-one'||a==='consume-all'){const item=state.items.find(i=>i.id===id);if(item){const result=await consumeExact(id,a==='consume-all'?item.quantity:Math.min(1,item.quantity));if($('#item-sheet').open)$('#item-sheet').close();notify(`${item.name}を${a==='consume-all'?'使い切りました':'減らしました'}`,result.id);await refresh();}}
    if(a==='undo'){await undo(id);notify('元に戻しました');await refresh();}
    if(a==='camera-start')await startCamera();
    if(a==='camera-stop'){endDemo();await scanner.stop();cameraUI(false);}
    if(a==='mode'){mode=button.dataset.mode;scanner.machine.mode=mode;scanner.machine.cancel();$('#mode-add').classList.toggle('active',mode==='add');$('#mode-consume').classList.toggle('active',mode==='consume');}
    if(a==='pause'){scanner.setPaused(!scanner.paused);button.textContent=scanner.paused?'再開':'一時停止';$('#camera-status').textContent=scanner.paused?'一時停止中':'読み取り中';}
    if(a==='edit-scan'){const item=scanState.pending||scanState.target;if(item)openEditor(candidateInput(item),mode==='consume'?'scan-consume':'scan-add');}
    if(a==='cancel-scan')scanner.machine.cancel();
    if(a==='next-same')scanner.machine.reset();
    if(a==='close-editor')closeEditor();
    if(a==='add-staple'){$('#staple-error').textContent='';$('#staple-editor').showModal();}
    if(a==='close-staple')$('#staple-editor').close();
    if(a==='remove-staple'){await mutate(s=>s.staples=s.staples.filter(i=>i.id!==id));await refresh();}
    if(a==='remove-shopping'){await mutate(s=>s.shopping=s.shopping.filter(i=>i.id!==id));await refresh();}
    if(a==='load-model')await loadModel();
    if(a==='cancel-model')vision.cancelLoad();
    if(a==='model-file'){if(isNative){try{const importing=vision.importModel();if(view==='settings')renderSettings();await importing;savedModel=true;await loadModel();}catch(error){if(error.name!=='AbortError')notify(error.message);}finally{if(view==='settings')renderSettings();}}else $('#model-file').click();}
    if(a==='unload-model'){await vision.unload();runtimeStatus='Gemmaのメモリを解放しました';renderSettings();}
    if(a==='generate-recipes')await generateRecipes();
    if(a==='export')exportData();
    if(a==='import')$('#backup-file').click();
    if(a==='demo-start')startDemo();
    if(a.startsWith('demo-')&&a!=='demo-start')demoObserve(a.slice(5));
  }catch(error){notify(error.message);}
});
window.addEventListener('hashchange',()=>navigate(location.hash.slice(1)));
document.addEventListener('visibilitychange',()=>{if(document.hidden){endDemo();cameraUI(false);}else refresh().catch(error=>notify(error.message));});
if('BroadcastChannel'in window){const channel=new BroadcastChannel('refrigerator-assistant');channel.onmessage=()=>refresh().catch(()=>{});}
async function init(){try{await refresh();$('#scan-location').value=state.settings.location;await navigate(location.hash.slice(1)||'home');if(!isNative&&'serviceWorker'in navigator)navigator.serviceWorker.register('./sw.js').catch(()=>{});}catch(error){$('#view-home').innerHTML=`<div class="notice danger">データ保存を初期化できませんでした。プライベートブラウズや空き容量を確認してください。<br>${esc(error.message)}</div>`;}}
init();
vision.hasSavedModel().then(saved=>{savedModel=saved;if(view==='settings')renderSettings();}).catch(()=>{});
