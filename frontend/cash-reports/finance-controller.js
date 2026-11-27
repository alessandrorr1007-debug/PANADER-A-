'use strict';
function localBusinessDate(now=new Date()){
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
 const p=Object.fromEntries(parts.map(x=>[x.type,x.value]));return p.year+'-'+p.month+'-'+p.day;
}
function reportDays(days,now=new Date()){
 if(![7,30,90].includes(days))throw Error('Período inválido');
 const end=new Date(localBusinessDate(now)+'T00:00:00Z');return Array.from({length:days},(_,i)=>new Date(end.getTime()-(days-1-i)*86400000).toISOString().slice(0,10));
}
function moneyCents(raw){
 const s=String(raw),neg=s.startsWith('-'),a=neg?s.slice(1):s;
 if(!/^\d+(?:\.\d{1,2})?$/.test(a))throw Error('Importe inválido');
 const [w,f='']=a.split('.');const n=BigInt(w)*100n+BigInt(f.padEnd(2,'0'));return neg?-n:n;
}
function summarizeFinance(days,sales,purchases){
 const s=new Map(sales.map(r=>[r.business_date,r])),p=new Map(purchases.map(r=>[r.business_date,r]));
 const totals={revenue:0n,units:0n,purchases:0n,cost:0n,margin:0n,count:0n};
 const rows=days.map(day=>{const a=s.get(day),b=p.get(day);const row={day,revenue:moneyCents(a?.revenue??0),units:BigInt(a?.units_sold??0),purchases:moneyCents(b?.received_cost??0),cost:moneyCents(a?.estimated_ingredient_cost??0),margin:moneyCents(a?.estimated_ingredient_margin??0),count:BigInt(a?.sale_count??0)};for(const k of Object.keys(totals))totals[k]+=row[k];return row;});
 return {rows,totals};
}
function createFinanceController({api,run,onChange=async()=>{}}){
 const $=id=>document.getElementById(id),tracker=requestTracker(()=>crypto.randomUUID());let scope=null,loaded=false,shifts=[],current=null,permissions={};
 const money=n=>'S/ '+centsText(n),fmt=n=>n==null?'—':money(moneyCents(n)),date=n=>n?new Date(n).toLocaleString('es-PE',{timeZone:'America/Lima'}):'—';
 const msg=t=>{$('finance-message').textContent=t;};
 const ids=['fin-shifts','fin-entries','fin-chart','fin-days','fin-shift-select'];
 const metrics=['fin-opening','fin-cash-sales','fin-digital','fin-in','fin-out','fin-expected','fin-revenue','fin-units','fin-purchases','fin-cost','fin-margin','fin-sales-count','fin-production-cost','fin-production-margin'];
 function clear(logout=false){scope=null;loaded=false;shifts=[];current=null;permissions={};$('finance-area').hidden=true;$('finance-content').hidden=true;$('cash-entry-form').reset();$('cash-entry-form').hidden=true;$('fin-period').value='30';ids.forEach(id=>$(id).replaceChildren());metrics.forEach(id=>$(id).textContent='—');$('fin-range').textContent='';$('fin-shift-status').textContent='';msg('');if(logout)tracker.clear();}
 function row(id,values){const tr=document.createElement('tr');for(const v of values){const td=document.createElement('td');td.textContent=String(v);tr.append(td);}$(id).append(tr);}
 async function entries(){ $('fin-entries').replaceChildren();const shift=shifts.find(s=>s.shift_id===$('fin-shift-select').value);if(!scope||!shift){row('fin-entries',['Sin turno','—','—','—']);return;}const data=await api.cashEntries(scope.bakery,shift.shift_id);if(!Array.isArray(data))throw Error('Invalid entries');for(const e of data)row('fin-entries',[date(e.created_at),e.direction==='in'?'Ingreso':'Egreso',fmt(e.amount),e.reason]);if(!data.length)row('fin-entries',['Sin movimientos','—','—','—']);}
 async function report(){
 const days=reportDays(Number($('fin-period').value)),from=days[0],to=days.at(-1),{bakery,branch}=scope;
 const [s,p,full]=await Promise.all([collectPages(c=>api.dailySales(bakery,branch,from,to,c),'business_date',90),collectPages(c=>api.dailyPurchases(bakery,branch,from,to,c),'business_date',90),collectPages(c=>api.productionMargins(bakery,branch,from,to,c),'business_date',90)]);
 const {rows,totals:t}=summarizeFinance(days,s,p);$('fin-production-cost').textContent=money(full.reduce((sum,r)=>sum+moneyCents(r.production_cost),0n));$('fin-production-margin').textContent=money(full.reduce((sum,r)=>sum+moneyCents(r.production_margin),0n));
 $('fin-range').textContent=from+' al '+to+' · hora de Perú';
 for(const [id,value] of Object.entries({'fin-revenue':money(t.revenue),'fin-units':t.units.toString(),'fin-purchases':money(t.purchases),'fin-cost':money(t.cost),'fin-margin':money(t.margin),'fin-sales-count':t.count.toString()}))$(id).textContent=value;
 $('fin-chart').replaceChildren();$('fin-days').replaceChildren();const peak=rows.reduce((m,r)=>r.revenue>m?r.revenue:m,0n);
 for(const r of rows){const barRow=document.createElement('div');barRow.className='fin-bar-row';const lab=document.createElement('span');lab.textContent=r.day.slice(5);const track=document.createElement('div');track.className='fin-bar-track';const bar=document.createElement('div');bar.className='fin-bar';bar.style.width=(peak>0n?Number(r.revenue*10000n/peak)/100:0)+'%';track.append(bar);const val=document.createElement('span');val.className='fin-bar-value';val.textContent=money(r.revenue);barRow.append(lab,track,val);$('fin-chart').append(barRow);row('fin-days',[r.day,money(r.revenue),r.units.toString(),money(r.purchases),money(r.margin)]);}
 }
 async function refresh(){if(!scope)return;loaded=false;$('finance-content').hidden=true;try{
 const prior=$('fin-shift-select').value;const {bakery,branch,role}=scope;
 const [ss,sub,open]=await Promise.all([api.cashShifts(bakery,branch),api.subscription(bakery),api.cashOpen(bakery,branch)]);
 if(![ss,sub,open].every(Array.isArray)||open.length>1)throw Error('Invalid response');
 shifts=ss;current=open[0]?ss.find(x=>x.shift_id===open[0].shift_id)||null:null;
 // An unusually old open shift must never disappear from the list.
 if(open.length&&!current)throw Error('Open shift not in history');
 permissions=modulePermissions(scope,sub[0],'cash');$('fin-shift-status').textContent=current?'Caja abierta desde '+date(current.opened_at):'No hay un turno abierto. Abre caja en Compras y punto de venta.';
 for(const [id,key] of Object.entries({'fin-opening':'opening_amount','fin-cash-sales':'cash_sales','fin-digital':'digital_sales','fin-in':'cash_in','fin-out':'cash_out','fin-expected':'expected_cash'}))$(id).textContent=current?fmt(current[key]):'—';
 $('cash-entry-form').hidden=!permissions.manager||!current;$('fin-shifts').replaceChildren();$('fin-shift-select').replaceChildren();
 for(const c of shifts){row('fin-shifts',[date(c.opened_at),c.closed_at?date(c.closed_at):'Abierta',fmt(c.expected_cash),fmt(c.counted_cash),fmt(c.difference)]);const op=document.createElement('option');op.value=c.shift_id;op.textContent=date(c.opened_at)+(c.closed_at?' · Cerrado':' · Abierto');$('fin-shift-select').append(op);}
 if(!shifts.length)row('fin-shifts',['Sin turnos','—','—','—','—']);if(shifts.some(x=>x.shift_id===prior))$('fin-shift-select').value=prior;else if(current)$('fin-shift-select').value=current.shift_id;
 if(permissions.has('cash'))await entries();if(permissions.has('reports'))await report();loaded=true;$('finance-content').hidden=false;msg(permissions.active?'':'Suscripción vencida o inactiva: consulta; cierre en el módulo comercial.');
 }catch(e){loaded=false;msg('No se pudieron cargar caja y reportes. Actualiza para volver a consultar.');if(!api.hasSession())throw e;}}
 async function open(next){scope=next;$('finance-area').hidden=false;$('finance-scope').textContent=next.label;await refresh();}
 $('finance-reload').addEventListener('click',()=>run(refresh));$('fin-period').addEventListener('change',()=>run(refresh));$('fin-shift-select').addEventListener('change',()=>run(async()=>{try{await entries();}catch(e){msg('No se pudieron consultar los movimientos.');if(!api.hasSession())throw e;}}));
 $('cash-entry-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!loaded||!permissions.manager||!current||!$('fin-confirm').checked)return;let amount;try{amount=scaled($('fin-amount').value,2,99999999999n);}catch{msg('Importe inválido.');return;}const direction=$('fin-direction').value,reason=$('fin-reason').value.trim();if(!reason){msg('Escribe el motivo.');return;}if(direction==='out'&&amount>moneyCents(current.expected_cash)){msg('Efectivo insuficiente según la última consulta.');return;}
 const value=Number(amount)/100,payload=[scope.bakery,scope.branch,current.shift_id,direction,value,reason];
 try{await api.addCashEntry(scope.bakery,scope.branch,current.shift_id,tracker.id(payload),direction,value,reason);tracker.complete(payload);}catch(e){msg('Movimiento no confirmado. Consulta el historial antes de repetir; conserva los mismos datos en esta sesión.');if(!api.hasSession())throw e;return;}
 $('cash-entry-form').reset();await refresh();if(loaded)msg('Movimiento de caja registrado.');await onChange();});});
 return {open,clear,refresh};
}
if(typeof module!=='undefined'){const {centsText}=require('../commerce/commerce-controller.js');module.exports={localBusinessDate,reportDays,moneyCents,summarizeFinance};}
