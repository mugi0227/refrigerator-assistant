/** Pure domain logic. No browser globals, model calls, or hidden network access. */
export const DAY = 86400000;
export const LOCATIONS = { fridge: '冷蔵', freezer: '冷凍', pantry: '常温' };
export const EXPIRY = { best_before: '賞味期限', use_by: '消費期限', estimate: '使い切り目安', unknown: '期限未設定' };
export const DEFAULTS = { sound: true, interval: 1200, confirmMs: 5000, location: 'fridge', externalLookup: false };
// Editable planning reminders, NOT scientifically determined storage/safety guarantees.
export const PRODUCE = {
  'トマト': { emoji: '🍅', days: 5, aliases: ['tomato', 'tomatoes', 'とまと'] },
  'にんじん': { emoji: '🥕', days: 7, aliases: ['carrot', 'carrots', '人参', 'ニンジン'] },
  'キャベツ': { emoji: '🥬', days: 7, aliases: ['cabbage', 'きゃべつ'] },
  'ブロッコリー': { emoji: '🥦', days: 3, aliases: ['broccoli', 'ぶろっこりー'] },
  'ほうれん草': { emoji: '🥬', days: 3, aliases: ['spinach', 'ホウレンソウ'] },
  'きゅうり': { emoji: '🥒', days: 4, aliases: ['cucumber', 'キュウリ', '胡瓜'] },
  '玉ねぎ': { emoji: '🧅', days: 7, aliases: ['onion', 'onions', 'たまねぎ', 'タマネギ'] },
  'じゃがいも': { emoji: '🥔', days: 7, aliases: ['potato', 'potatoes', 'ジャガイモ'] },
  'ピーマン': { emoji: '🫑', days: 5, aliases: ['green pepper', 'bell pepper'] },
  'なす': { emoji: '🍆', days: 4, aliases: ['eggplant', 'ナス', '茄子'] },
  'レタス': { emoji: '🥬', days: 3, aliases: ['lettuce'] },
  '大根': { emoji: '🥬', days: 7, aliases: ['daikon', 'だいこん', 'ダイコン'] },
  'バナナ': { emoji: '🍌', days: 3, aliases: ['banana', 'bananas'] },
  'りんご': { emoji: '🍎', days: 7, aliases: ['apple', 'apples', 'リンゴ', '林檎'] },
  'きのこ': { emoji: '🍄', days: 3, aliases: ['mushroom', 'mushrooms', 'キノコ'] }
};
export function cleanName(value) { return String(value ?? '').normalize('NFKC').trim().slice(0, 80); }
export function canonicalName(value) {
  const name = cleanName(value), lower = name.toLowerCase();
  for (const [key, v] of Object.entries(PRODUCE)) if (key === name || v.aliases.includes(lower)) return key;
  if (['egg', 'eggs', 'たまご', 'タマゴ', '鶏卵'].includes(lower)) return '卵';
  if (['milk', 'ミルク'].includes(lower)) return '牛乳';
  return name;
}
// Icons for names people type or packages report. First match wins, so narrower words come first (牛乳 before 牛).
const ICONS = [
  [/卵|たまご|タマゴ|egg/i,'🥚'], [/ヨーグルト|yogurt/i,'🥣'], [/チーズ|cheese/i,'🧀'], [/バター|マーガリン|butter/i,'🧈'],
  [/アイス|ice\s*cream/i,'🍨'], [/プリン|ゼリー/,'🍮'], [/ケーキ|cake/i,'🍰'], [/チョコ/,'🍫'],
  [/牛乳|豆乳|ミルク|乳飲料|milk/i,'🥛'], [/ジュース|juice/i,'🧃'], [/コーラ|サイダー|炭酸|ソーダ/,'🥤'], [/コーヒー|coffee/i,'☕'],
  [/茶|tea/i,'🍵'], [/ビール|beer/i,'🍺'], [/ワイン|wine/i,'🍷'], [/日本酒|酒/,'🍶'], [/^水$|ウォーター|water/i,'💧'],
  [/豆腐|とうふ|tofu/i,'⬜'], [/納豆|なっとう/,'🫘'], [/枝豆|えだまめ|そら豆|えんどう/,'🫛'],
  [/ベーコン|ハム|bacon|ham/i,'🥓'], [/ソーセージ|ウインナー|ウィンナー|sausage/i,'🌭'], [/鶏|チキン|ささみ|手羽|chicken/i,'🍗'],
  [/肉|豚|牛|ステーキ|meat|pork|beef/i,'🥩'], [/えび|エビ|海老|shrimp/i,'🦐'], [/^いか|イカ|烏賊|たこ|タコ/,'🦑'], [/あさり|しじみ|貝|牡蠣/,'🦪'],
  [/刺身|寿司|すし/,'🍣'], [/ちくわ|かまぼこ|はんぺん/,'🍥'], [/魚|鮭|さけ|サーモン|さば|鯖|あじ|鯵|ぶり|鰤|たら|鱈|まぐろ|fish|salmon/i,'🐟'],
  [/餃子|ぎょうざ|ギョーザ/,'🥟'], [/弁当|惣菜|そうざい/,'🍱'], [/ピザ|pizza/i,'🍕'], [/パスタ|スパゲ/,'🍝'],
  [/うどん|そば|ラーメン|麺|焼きそば|noodle/i,'🍜'], [/ご飯|ごはん|米|おにぎり|rice/i,'🍚'], [/パン|bread/i,'🍞'],
  [/白菜|小松菜|水菜|チンゲン|青菜|ほうれん/,'🥬'], [/ねぎ|ネギ|葱|大葉|バジル|パセリ|ハーブ|ニラ|にら/,'🌿'], [/もやし|スプラウト|豆苗/,'🌱'],
  [/さつまいも|さつま芋/,'🍠'], [/いも|芋/,'🥔'], [/かぼちゃ|南瓜/,'🎃'], [/とうもろこし|コーン|corn/i,'🌽'], [/にんにく|ニンニク|garlic/i,'🧄'],
  [/しょうが|生姜|ショウガ|ginger/i,'🫚'], [/唐辛子|とうがらし|チリ/,'🌶️'], [/パプリカ/,'🫑'], [/しいたけ|えのき|しめじ|まいたけ|エリンギ/,'🍄'],
  [/アボカド|avocado/i,'🥑'], [/レモン|lemon/i,'🍋'], [/みかん|オレンジ|orange/i,'🍊'], [/いちご|苺|イチゴ|strawberr/i,'🍓'],
  [/ぶどう|葡萄|ブドウ|grape/i,'🍇'], [/もも|桃|peach/i,'🍑'], [/メロン|melon/i,'🍈'], [/すいか|スイカ|西瓜/,'🍉'], [/キウイ|kiwi/i,'🥝'],
  [/パイン|pineapple/i,'🍍'], [/さくらんぼ|チェリー|cherr/i,'🍒'], [/ブルーベリー|blueberr/i,'🫐'], [/梨|pear/i,'🍐'], [/マンゴー|mango/i,'🥭'],
  [/キムチ|漬物|漬け|ジャム|味噌|みそ|佃煮/,'🫙'], [/マヨ|ケチャップ|ソース|ドレッシング|醤油|しょうゆ|ポン酢|たれ|タレ/,'🧴'], [/冷凍/,'🧊']
];
export function emoji(name) {
  const canonical = canonicalName(name);
  if (PRODUCE[canonical]) return PRODUCE[canonical].emoji;
  return ICONS.find(([pattern]) => pattern.test(canonical))?.[1] ?? '🍽️';
}
export function today(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}
export function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y,m,d] = value.split('-').map(Number), date = new Date(Date.UTC(y,m-1,d));
  return y >= 2000 && y <= 2099 && date.getUTCFullYear() === y && date.getUTCMonth() === m-1 && date.getUTCDate() === d;
}
export function addDays(date, days) { return new Date(Date.parse(date+'T00:00:00Z') + days*DAY).toISOString().slice(0,10); }
export function daysLeft(date, now = today()) { return validDate(date) ? Math.round((Date.parse(date)-Date.parse(now))/DAY) : null; }
export function planDate(name, freshness = 1, now = today(), overrides = {}) {
  const base = Number(overrides[canonicalName(name)] ?? PRODUCE[canonicalName(name)]?.days ?? 3);
  const factor = [0.4, 1, 1.2][Math.min(2, Math.max(0, Number(freshness)))];
  return addDays(now, Math.max(1, Math.round(base*factor)));
}
/** Never infer an absent year or silently normalize impossible dates. */
export function dateFromLabel(raw) {
  const text = String(raw ?? '').normalize('NFKC');
  const m = text.match(/(?:^|[^\d])(20\d{2}|\d{2})\s*[年./\-]\s*(\d{1,2})\s*[月./\-]\s*(\d{1,2})(?:日|\b)/);
  if (!m) return null;
  const y = m[1].length === 2 ? '20'+m[1] : m[1];
  const result = `${y}-${m[2].padStart(2,'0')}-${m[3].padStart(2,'0')}`;
  return validDate(result) ? result : null;
}
export function verifiedExpiry(expiry, now = today()) {
  if (!expiry || !['best_before','use_by'].includes(expiry.type) || !validDate(expiry.date)) return null;
  const raw = cleanName(expiry.raw), label = String(expiry.label ?? '').normalize('NFKC');
  const typeMatches = expiry.type === 'best_before' ? /賞味|best\s*before/i.test(label) : /消費|use\s*by|expir/i.test(label);
  if (!typeMatches || dateFromLabel(raw) !== expiry.date) return null;
  // Extreme dates require manual review, not "correction" by the model.
  const distance = daysLeft(expiry.date, now);
  if (distance < -366 || distance > 3653) return null;
  return { type: expiry.type, date: expiry.date, raw, label: label.slice(0,80) };
}
export function parseObservation(text) {
  if (typeof text !== 'string' || text.length > 12000) throw new Error('AI出力が不正です');
  const stripped = text.replace(/<think>[\s\S]*?<\/think>/g,'').replace(/```(?:json)?/g,'').trim();
  const a = stripped.indexOf('{'), b = stripped.lastIndexOf('}');
  if (a < 0 || b < a) throw new Error('JSONとして読み取れませんでした');
  const obj = JSON.parse(stripped.slice(a,b+1));
  if (!obj || !['none','produce','packaged','eggs'].includes(obj.kind)) throw new Error('食品の種別を確認できませんでした');
  const name = canonicalName(obj.name);
  const count = Number.isInteger(obj.count) && obj.count >= 1 && obj.count <= 99 ? obj.count : null;
  return { kind: obj.kind, name, count, targetMatches: obj.targetMatches === true,
    multiple: obj.multiple === true, expiry: verifiedExpiry(obj.expiry), uncertain: obj.uncertain === true,
    raw: text.slice(0,3000) };
}
export function validGtin(code) {
  if (!/^\d{8}$|^\d{12,14}$/.test(code)) return false;
  const digits = [...code].map(Number); let sum = 0;
  for (let i=digits.length-2, weight=3;i>=0;i--,weight=4-weight) sum += digits[i]*weight;
  return (10 - sum%10)%10 === digits.at(-1);
}
function gsDate(raw) {
  if (!/^\d{6}$/.test(raw ?? '')) return null;
  const year = 2000+Number(raw.slice(0,2)), month = Number(raw.slice(2,4));
  if (month<1 || month>12) return null;
  const day = Number(raw.slice(4)) || new Date(Date.UTC(year,month,0)).getUTCDate();
  const date = `${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
  return validDate(date) ? date : null;
}
/** Limited GS1 parser: GTIN + AI15/17. Unknown AIs stop parsing; arbitrary QR URLs are never fetched. */
export function parseBarcode(value) {
  const raw = String(value ?? '').trim();
  if (validGtin(raw)) return { barcode: raw.padStart(14,'0'), expiry: null };
  let fields = {};
  if (/^https:\/\//i.test(raw)) {
    try { const url = new URL(raw), parts = url.pathname.split('/').filter(Boolean);
      for (let i=0;i+1<parts.length;i+=2) fields[parts[i]] = parts[i+1];
      for (const [key,val] of url.searchParams) fields[key] = val;
    } catch { return null; }
  } else if (/\(01\)/.test(raw)) {
    for (const m of raw.matchAll(/\((\d{2,4})\)([^()]+)/g)) fields[m[1]]=m[2];
  } else {
    let s = raw.replace(/^\][A-Za-z]\d/,'');
    while(s.length) {
      s=s.replace(/^\x1d/,''); const ai=s.slice(0,2);
      const len = ({ '01':14,'15':6,'17':6,'11':6,'13':6 })[ai];
      if(len) { if(s.length < len+2) return null; fields[ai]=s.slice(2,len+2); s=s.slice(len+2); }
      else if(['10','21'].includes(ai)) { const end=s.indexOf('\x1d',2); if(end<0) break; s=s.slice(end+1); }
      else break;
    }
  }
  if (!/^\d{14}$/.test(fields['01'] ?? '') || !validGtin(fields['01'])) return null;
  const ai = fields['17'] ? '17' : fields['15'] ? '15' : null, date=ai && gsDate(fields[ai]);
  return { barcode: fields['01'], expiry: date ? { type: ai==='17' ? 'use_by':'best_before', date, raw: fields[ai], label: `GS1 AI ${ai}` } : null };
}
export function createItem(input, now = today()) {
  const name=cleanName(input.name), quantity=Number(input.quantity ?? 1), unit=cleanName(input.unit || '個');
  if(!name || name.startsWith('未登録の商品')) throw new Error('食品名を入力してください');
  if(!Number.isFinite(quantity) || quantity<=0 || quantity>100000) throw new Error('数量は0より大きい数で入力してください');
  if(!['個','本','パック','束','袋','g','ml'].includes(unit)) throw new Error('数量の単位を確認してください');
  const location = input.location || 'fridge';
  if(!Object.hasOwn(LOCATIONS, location)) throw new Error('保存場所が不正です');
  const expiryType = input.expiryType || 'unknown';
  if(!Object.hasOwn(EXPIRY, expiryType)) throw new Error('期限の種類が不正です');
  const expiryDate = input.expiryDate || null;
  if(expiryDate && !validDate(expiryDate)) throw new Error('期限の日付を確認してください');
  if(expiryType !== 'unknown' && !expiryDate) throw new Error('期限の日付が必要です');
  if(expiryType === 'unknown' && expiryDate) throw new Error('期限の種類を選択してください');
  return { id: input.id || crypto.randomUUID(), name, quantity, unit, location,
    kind: ['produce','packaged','eggs'].includes(input.kind) ? input.kind : 'packaged',
    barcode: input.barcode && validGtin(input.barcode) ? input.barcode.padStart(14,'0') : null,
    expiryType, expiryDate, freshness: Math.min(2,Math.max(0, Number(input.freshness ?? 1))),
    addedOn: validDate(input.addedOn) ? input.addedOn : now, opened: input.opened===true,
    notes: cleanName(input.notes), source: ['camera','manual','demo'].includes(input.source) ? input.source : 'manual', rev: Number(input.rev)||1 };
}
export function matches(item, candidate) {
  if(item.location !== candidate.location) return false;
  if(candidate.barcode && item.barcode) return item.barcode === candidate.barcode.padStart(14,'0');
  return canonicalName(item.name).toLowerCase() === canonicalName(candidate.name).toLowerCase();
}
export function consumePlan(items, candidate, quantity) {
  const amount=Number(quantity), unit=candidate.unit || '個';
  if(!Number.isFinite(amount) || amount<=0) throw new Error('消費量を確認してください');
  const lots=items.filter(i=>i.quantity>0 && matches(i,candidate) && i.unit===unit)
    .sort((a,b)=>(a.expiryDate||'9999').localeCompare(b.expiryDate||'9999') || a.addedOn.localeCompare(b.addedOn));
  if(lots.reduce((s,i)=>s+i.quantity,0)+1e-8<amount) throw new Error('一致する在庫が足りません。数量・保存場所・単位を確認してください');
  let rest=amount; const changes=[];
  for(const lot of lots) { if(rest<=1e-8) break; const take=Math.min(rest,lot.quantity);
    changes.push({ before:{...lot}, after:{...lot,quantity:Math.round((lot.quantity-take)*1000)/1000,rev:lot.rev+1} }); rest-=take; }
  return changes;
}
export function emptyState() { return { version:1, items:[], events:[], staples:[], shopping:[], settings:{...DEFAULTS}, productCache:{} }; }
export function shoppingNeeds(state) {
  return state.staples.map(s=> { const have=state.items.filter(i=>canonicalName(i.name)===canonicalName(s.name) && i.unit===s.unit).reduce((n,i)=>n+i.quantity,0);
    return {...s, have, buy:Math.max(0,s.target-have)}; }).filter(s=>s.have<s.minimum);
}
export function validateBackup(data) {
  if(!data || data.version!==1 || !Array.isArray(data.items) || data.items.length>10000 || !Array.isArray(data.staples) || !Array.isArray(data.shopping)) throw new Error('対応するバックアップ形式ではありません');
  const state=emptyState(); state.items=data.items.map(i=>createItem({...i,quantity:Math.max(0.001,i.quantity)})).map((i,index)=>({...i,quantity:data.items[index].quantity}));
  if(state.items.some(i=>!Number.isFinite(i.quantity)||i.quantity<0)) throw new Error('在庫の数量が不正です');
  if(new Set(state.items.map(i=>i.id)).size!==state.items.length || state.items.some(i=>typeof i.id!=='string'||i.id.length>80)) throw new Error('在庫IDが不正です');
  state.staples=data.staples.slice(0,200).map(s=>validateStaple(s));
  state.shopping=data.shopping.slice(0,200).map(s=>({id:crypto.randomUUID(),name:cleanName(s.name),done:s.done===true})).filter(s=>s.name);
  state.settings={...DEFAULTS, sound:data.settings?.sound!==false, location:Object.hasOwn(LOCATIONS,data.settings?.location)?data.settings.location:'fridge'};
  return state; // Do not import executable/model URLs, cache entries, or undo events from untrusted backups.
}
export function validateStaple(s) {
  const name=cleanName(s.name), unit=cleanName(s.unit||'個'), minimum=Number(s.minimum), target=Number(s.target);
  if(!name || !['個','本','パック','束','袋','g','ml'].includes(unit) || !Number.isFinite(minimum)||minimum<=0||minimum>100000||!Number.isFinite(target)||target<minimum||target>100000) throw new Error('補充ラインと目標数量を確認してください');
  return { id:s.id || crypto.randomUUID(),name,unit,minimum,target };
}

/** Camera coordinator: delayed commit, temporal agreement, target latch and date evidence. */
export class ScanMachine {
  constructor({ onChange=()=>{}, onDetect=()=>{}, onCommit=()=>{}, confirmMs=5000 }={}) {
    Object.assign(this,{ onChange,onDetect,onCommit,confirmMs }); this.mode='add'; this.location='fridge'; this.reset();
  }
  reset() { this.target=null; this.pending=null; this.lock=null; this.votes=null; this.printedVotes=null; this.emptySince=null; this.emptyCount=0; this.revision=(this.revision||0)+1; this.emit(); }
  emit(message='') { this.onChange({target:this.target,pending:this.pending,lock:this.lock,message,revision:this.revision}); }
  key(x) { return x.barcode ? `b:${x.barcode}` : `n:${canonicalName(x.name).toLowerCase()}`; }
  isSame(a,b) { return !!a && !!b && (a.barcode && b.barcode ? a.barcode===b.barcode : canonicalName(a.name)===canonicalName(b.name)); }
  select(candidate, now) {
    this.emptySince=null; this.emptyCount=0;
    if(this.lock && this.isSame(this.lock,candidate)) { this.emit('登録済みです。次の食品を映してください'); return false; }
    if(this.target && this.isSame(this.target,candidate)) { Object.assign(this.target,candidate); return true; }
    if(this.pending) this.commit();
    this.target={...candidate,location:this.location,seenAt:now}; this.votes=null; this.printedVotes=null; this.revision++;
    this.onDetect(); this.emit(); return true;
  }
  barcode(data, known, now=Date.now()) {
    const candidate={barcode:data.barcode,name:known?.name||'未登録の商品',kind:known?.kind||'packaged',quantity:1,unit:known?.unit||'個'};
    // Fuse a barcode discovered after vision identified this same physical package.
    if(this.lock && !this.lock.barcode && (!known || canonicalName(known.name)===canonicalName(this.lock.name))) { this.lock.barcode=data.barcode; this.emit('登録済みです。次の食品を映してください'); return; }
    if(this.target && !this.target.barcode && this.target.kind!=='produce' && (!known || canonicalName(known.name)===canonicalName(this.target.name))) {
      this.target.barcode=data.barcode; if(this.pending)this.pending.barcode=data.barcode;
      if(data.expiry)this.target.expiry=data.expiry; this.revision++; this.emit(); return;
    }
    if(this.target?.barcode===data.barcode) { this.emptySince=null; this.emptyCount=0;
      if(known && this.target.name==='未登録の商品')Object.assign(this.target,known);
      if(data.expiry)this.target.expiry=data.expiry;
      if(this.target.name!=='未登録の商品' && !['eggs','produce'].includes(this.target.kind) && (this.mode==='consume'||this.target.expiry?.label?.startsWith('GS1')))this.stage(now);
      return;
    }
    if(!this.select(candidate,now)) return;
    if(this.mode==='consume' && known && !['eggs','produce'].includes(known.kind)) this.stage(now);
    else if(data.expiry && known) { this.target.expiry=data.expiry; this.stage(now); }
    else if(data.expiry) this.target.expiry=data.expiry;
    this.emit();
  }
  observe(obs, now=Date.now()) {
    if(obs.kind==='none' && !obs.expiry) {
      this.emptySince??=now; this.emptyCount++;
      if(this.emptyCount>=2 && now-this.emptySince>=1000 && !this.pending) { this.lock=null; this.target=null; this.votes=null; this.revision++; this.emit(); }
      return;
    }
    this.emptySince=null; this.emptyCount=0;
    if(obs.multiple || obs.uncertain) { this.pending=null; this.votes=null; this.emit('食品を1種類ずつ、はっきり映してください'); return; }
    if(obs.kind==='none' && !this.target) return;
    const existing=this.target;
    const nameCompatible=existing && (!obs.name || existing.name==='未登録の商品' || canonicalName(existing.name)===obs.name || existing.name.includes(obs.name) || obs.name.includes(existing.name));
    const continuing=existing && nameCompatible && (obs.targetMatches || canonicalName(existing.name)===obs.name || (existing.name==='未登録の商品' && obs.name));
    const name=continuing && existing.name!=='未登録の商品' ? existing.name : obs.name;
    if(!name || name==='未登録の商品') { this.emit('商品名も映してください'); return; }
    const kind=continuing && obs.kind==='none' ? existing.kind : obs.kind;
    const counted=(kind==='produce'||kind==='eggs');
    const candidate={name,kind,quantity:counted ? obs.count : 1,unit:continuing ? existing.unit : '個',barcode:continuing ? existing.barcode : null};
    // Never silently interpret a null/occluded count as one.
    if(candidate.quantity===null) { this.pending=null; this.votes=null; this.emit('個数が不明です。全体を映すか手入力してください'); return; }
    if(!this.select(candidate,now)) return;
    if(this.pending) {
      const contradiction=this.pending.quantity!==candidate.quantity || (obs.expiry && this.pending.expiry && (obs.expiry.date!==this.pending.expiry.date||obs.expiry.type!==this.pending.expiry.type));
      if(!contradiction)return;this.pending=null;this.votes=null;
    }
    if(obs.expiry && (continuing || obs.name===name)) this.target.expiry=obs.expiry;
    const ready=this.mode==='consume'||kind==='produce'||this.target.expiry;
    if(!ready) { this.votes=null; this.emit('賞味期限・消費期限の印字を映してください'); return; }
    // A date must agree in two fresh observations; do not reuse an earlier date in a new vote.
    if(this.mode==='add' && kind!=='produce' && !obs.expiry && !this.target.expiry?.label?.startsWith('GS1')) { this.votes=null; return; }
    const signature=JSON.stringify([this.key(this.target),candidate.quantity,this.target.expiry?.type,this.target.expiry?.date]);
    if(this.votes?.signature===signature) this.votes.count++; else this.votes={signature,count:1};
    if(this.votes.count>=2) this.stage(now); else this.emit('読み取りをもう一度照合しています');
  }
  stage(now) {
    if(!this.target || this.pending) return;
    this.pending={...this.target, deadline:now+this.confirmMs, mode:this.mode}; this.emit();
  }
  printed(result,now=Date.now()) {
    const target=this.target;
    if(!target?.barcode||target.kind!=='packaged'||this.mode!=='add')return;
    if(result.ambiguous){this.pending=null;this.printedVotes=null;delete target.expiry;delete target.printedDate;this.emit('日付が複数あります。期限の印字だけを映すか、編集で確認してください');return;}
    const expiry=verifiedExpiry(result.expiry);
    if(!expiry){
      this.printedVotes=null;
      if(result.candidate){
        if(this.pending&&this.pending.expiry?.date!==result.candidate.date){this.pending=null;delete target.expiry;}
        if(!target.expiry){target.printedDate={...result.candidate};this.emit('日付を読み取りました。賞味期限か消費期限かを確認してください');}
      }
      return;
    }
    if(this.pending){if(this.pending.expiry?.date===expiry.date&&this.pending.expiry?.type===expiry.type)return;this.pending=null;this.printedVotes=null;}
    target.expiry=expiry;delete target.printedDate;
    if(target.name==='未登録の商品'){this.printedVotes=null;this.emit('期限を読み取りました。編集から商品名を入力してください');return;}
    const signature=JSON.stringify([this.key(target),expiry.type,expiry.date]);
    if(this.printedVotes?.signature===signature)this.printedVotes.count++;else this.printedVotes={signature,count:1};
    if(this.printedVotes.count>=2)this.stage(now);else this.emit('期限をもう一度照合しています');
  }
  tick(now=Date.now()) { if(this.pending && now>=this.pending.deadline) this.commit(); }
  commit() {
    if(!this.pending) return;
    const item={...this.pending}; this.pending=null; this.lock={...item}; this.target=null; this.votes=null; this.printedVotes=null; this.revision++;
    this.onCommit(item); this.emit();
  }
  cancel() { if(this.target) this.lock={...this.target}; this.pending=null; this.target=null; this.votes=null; this.printedVotes=null; this.revision++; this.emit('取り消しました'); }
}
