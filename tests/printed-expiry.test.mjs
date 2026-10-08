import test from 'node:test';
import assert from 'node:assert/strict';
import {parsePrintedExpiry} from '../public/printed-expiry.js';
import {ScanMachine,parseBarcode,today,addDays,createItem} from '../public/core.js';
const line=(text,extra={})=>({text,confidence:0.95,...extra});
const read=lines=>parsePrintedExpiry(lines,'2026-10-09');
test('printed Japanese and English labels carry exact date evidence',()=>{
  assert.equal(read([line('賞味期限 ２０２６．１０．３１')]).expiry?.date,'2026-10-31');
  assert.equal(read([line('消費期限 26/10/12')]).expiry?.type,'use_by');
  assert.equal(read([line('BEST BEFORE 2026-10-31')]).expiry?.type,'best_before');
});
test('adjacent label must have overlapping, close bounding boxes',()=>{
  const label=line('賞味期限',{x:0.2,y:0.6,width:0.4,height:0.04});
  const date=line('2026.10.31',{x:0.2,y:0.54,width:0.4,height:0.04});
  assert.equal(read([label,date]).expiry?.date,'2026-10-31');
  assert.equal(read([label,{...date,y:0.1}]).expiry,null);
  assert.equal(read([label,{...date,x:0.7}]).expiry,null);
  assert.equal(read([line('賞味期限'),line('2026.10.31')]).expiry,null);
});
test('manufacturing date, missing year, impossible date, weak OCR are not expiry',()=>{
  for(const text of ['製造年月日 2026.10.01','賞味期限 10/31','賞味期限 2026.02.30','賞味期限 2026.13.01','LOT 261031'])
    assert.equal(read([line(text)]).expiry,null,text);
  assert.equal(read([line('賞味期限 2026.10.31',{confidence:0.3})]).candidate,null);
  assert.equal(read([line('製造年月日',{x:0.2,y:0.6,width:0.4,height:0.04}),line('2026.10.01',{x:0.2,y:0.54,width:0.4,height:0.04})]).candidate,null);
  assert.equal(read([line('製造年月日 2026.10.01'),line('賞味期限 2026.10.31')]).expiry?.date,'2026-10-31');
});
test('date alone is a review candidate; conflicting dates/types require review',()=>{
  const r=read([line('2026.10.31')]);assert.equal(r.expiry,null);assert.equal(r.candidate.date,'2026-10-31');
  assert.equal(read([line('賞味期限 2026.10.31'),line('賞味期限 2026.11.30')]).ambiguous,true);
  assert.equal(read([line('賞味期限 消費期限 2026.10.31')]).ambiguous,true);
  assert.equal(read([line('2026.10.31'),line('2026.11.30')]).ambiguous,true);
  assert.equal(read([line('賞味期限 2026.10.31'),line('賞味期限 2026.10.31')]).ambiguous,false);
});
const barcode=parseBarcode('4901330578909'),known={name:'じゃがりこ サラダ',kind:'packaged',unit:'個'};
const expiry=()=>parsePrintedExpiry([line(`賞味期限 ${addDays(today(),5)}`)]);
test('two reads with a known barcode stage one registration without image AI',()=>{
  const saved=[],m=new ScanMachine({onCommit:x=>saved.push(x),confirmMs:5});m.barcode(barcode,known,100);
  m.printed(expiry(),101);assert.equal(m.pending,null);m.printed(expiry(),102);assert.ok(m.pending);
  m.tick(108);assert.equal(saved.length,1);assert.equal(saved[0].name,known.name);
  m.barcode(barcode,known,109);m.printed(expiry(),110);m.printed(expiry(),111);m.tick(120);assert.equal(saved.length,1);
});
test('unknown product retains printed expiry but does not auto-register',()=>{
  const m=new ScanMachine();m.barcode(barcode,null);m.printed(expiry());m.printed(expiry());
  assert.equal(m.pending,null);assert.equal(m.target.expiry.date,addDays(today(),5));
  Object.assign(m.target,known);m.printed(expiry());assert.equal(m.pending,null);m.printed(expiry());assert.ok(m.pending);
});
test('unlabelled date never commits; editor requires an explicit expiry type',()=>{
  const m=new ScanMachine();m.barcode(barcode,known);const r=parsePrintedExpiry([line(addDays(today(),5))]);m.printed(r);m.printed(r);
  assert.equal(m.pending,null);assert.equal(m.target.expiry,undefined);assert.equal(m.target.printedDate.date,addDays(today(),5));
  assert.throws(()=>createItem({...known,quantity:1,location:'fridge',expiryType:'unknown',expiryDate:r.candidate.date}));
});
test('contradiction cancels a countdown, and reset does not reuse date votes',()=>{
  const m=new ScanMachine();m.barcode(barcode,known);m.printed(expiry());m.printed(expiry());assert.ok(m.pending);
  m.printed({ambiguous:true});assert.equal(m.pending,null);assert.equal(m.target.expiry,undefined);
  m.printed(expiry());assert.equal(m.pending,null);m.reset();m.barcode(barcode,known);m.printed(expiry());assert.equal(m.pending,null);
});
test('text recognition never guesses vegetable/egg count or consumes inventory',()=>{
  for(const kind of ['produce','eggs']){const m=new ScanMachine();m.barcode(barcode,{...known,kind});m.printed(expiry());m.printed(expiry());assert.equal(m.pending,null);}
  const m=new ScanMachine();m.mode='consume';m.barcode(barcode,null);m.printed(expiry());assert.equal(m.pending,null);
});
