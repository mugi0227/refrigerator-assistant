import {dateFromLabel,verifiedExpiry,today} from './core.js';

const dates=/(?:^|[^\d])(20\d{2}|\d{2})\s*[年./\-]\s*(\d{1,2})\s*[月./\-]\s*(\d{1,2})(?:日|\b)/g;
const manufacturing=/製造|加工|包装|packed\s*on|manufactur/i;
function types(text){return [...(/賞味\s*期限|best\s*before/i.test(text)?['best_before']:[]),...(/消費\s*期限|use\s*by/i.test(text)?['use_by']:[])];}
function close(a,b){
  const boxes=[a,b].map(l=>[l.x,l.y,l.width,l.height]);
  if(!boxes.every(v=>v.every(Number.isFinite)))return false;
  // Vision boxes use a bottom-left origin. Labels must overlap horizontally
  // and be on the same line or immediately above/below the printed date.
  const overlap=Math.min(a.x+a.width,b.x+b.width)-Math.max(a.x,b.x);
  return overlap>Math.min(a.width,b.width)*0.35&&Math.abs(a.y+a.height/2-b.y-b.height/2)<=Math.max(a.height,b.height)*2;
}

/** Conservative date evidence: never guess a year, expiry type, or food name. */
export function parsePrintedExpiry(input,now=today()){
  const lines=(Array.isArray(input)?input:[]).slice(0,100).filter(l=>typeof l?.text==='string'&&Number(l.confidence)>=0.55)
    .map(l=>({...l,text:l.text.normalize('NFKC').slice(0,200)}));
  const candidates=[],confirmed=[];
  for(const line of lines){
    if(manufacturing.test(line.text))continue;
    for(const match of line.text.matchAll(dates)){
      const raw=match[0].trim(),date=dateFromLabel(raw);if(!date)continue;
      // Reuse the range check without treating an unlabelled date as expiry.
      if(!verifiedExpiry({type:'best_before',date,raw,label:'賞味期限'},now))continue;
      candidates.push({date,raw});
      const own=types(line.text),near=lines.filter(l=>l!==line&&!manufacturing.test(l.text)&&close(line,l));
      // A date next to a manufacturing heading is not an expiry candidate.
      if(!own.length&&lines.some(l=>l!==line&&manufacturing.test(l.text)&&close(line,l))){candidates.pop();continue;}
      const associated=own.length?own:[...new Set(near.flatMap(l=>types(l.text)))];
      for(const type of associated){const label=type==='best_before'?'賞味期限':'消費期限';confirmed.push({type,date,raw,label});}
    }
  }
  const uniqueDates=[...new Map(candidates.map(c=>[c.date,c])).values()];
  const unique=[...new Map(confirmed.map(c=>[`${c.type}:${c.date}`,c])).values()];
  // Different dates elsewhere on the package are not automatically paired.
  if(unique.length>1||(!unique.length&&uniqueDates.length>1))return {ambiguous:true,expiry:null,candidate:null};
  if(unique.length===1)return {ambiguous:false,expiry:verifiedExpiry(unique[0],now),candidate:null};
  return {ambiguous:false,expiry:null,candidate:uniqueDates[0]||null};
}
