'use strict';
// Data functions are deliberately independent of DOM for reproducible tests.
async function collectPages(fetchPage,key,limit=5000){
 const rows=[];let cursor='';
 for(;;){const page=await fetchPage(cursor);if(!Array.isArray(page))throw Error('Invalid response');
 if(!page.length)return rows;
 for(const row of page){if(typeof row[key]!=='string'||row[key]<=cursor)throw Error('Invalid pagination');cursor=row[key];rows.push(row);}
 if(rows.length>limit)throw Error('Inventory too large for this view');}
}
function inventoryRows(ingredients,balances){
 const lookup=new Map(balances.map(b=>[b.ingredient_id,b]));
 return ingredients.map(i=>{const b=lookup.get(i.id);return {...i,quantity:b?Number(b.quantity):0,minimum:b?Number(b.minimum):0,missing:!b,low:!!b&&Number(b.quantity)<Number(b.minimum)};});
}
function inventoryPermissions(role,subscription,now=Date.now()){
 const active=!!subscription&&['trial','active'].includes(subscription.status)&&Date.parse(subscription.valid_until)>now;
 const manager=active&&['owner','admin'].includes(role);
 return {active,manager,movement:active&&['owner','admin','operator'].includes(role)};
}
const employeePermissionLabels=Object.freeze({inventory:'Almacén e insumos',recipes:'Crear recetas',production:'Registrar producción',purchases:'Compras y proveedores',sales:'Registrar ventas',prices:'Configurar precios',cash:'Gestionar caja',reports:'Consultar reportes'});
function modulePermissions(scope,subscription,manage,move=manage,now=Date.now()){
 const active=!!subscription&&['trial','active'].includes(subscription.status)&&Date.parse(subscription.valid_until)>now;
 const has=key=>scope?.role==='owner'||(Array.isArray(scope?.grants)&&scope.grants.includes(key));
 return {active,manager:active&&has(manage),movement:active&&has(move),has};
}
function decimal(raw,precision,max,allowZero=false){
 const s=String(raw).trim();if(!new RegExp('^\\d+(?:\\.\\d{1,'+precision+'})?$').test(s))throw Error('Cantidad inválida');
 const n=Number(s);if(!Number.isFinite(n)||n>max||n<0||(!allowZero&&n===0))throw Error('Cantidad fuera de rango');return n;
}
function requestTracker(makeId){
 const pending=new Map();
 return {id(payload){const key=JSON.stringify(payload);if(!pending.has(key))pending.set(key,makeId());return pending.get(key);},
 complete(payload){pending.delete(JSON.stringify(payload));},clear(){pending.clear();}};
}
// Convert exactly before sending canonical base quantities to PostgreSQL.
// 1 kg = 1000 g; 1 L = 1000 ml. No mass/volume conversions without density.
function allowedUnits(base){if(base==='kg')return ['kg','g'];if(base==='L')return ['L','ml'];if(base==='unit')return ['unit'];throw Error('Unidad base inválida');}
function baseQuantity(raw,unit,base,zero=false){
 if(!allowedUnits(base).includes(unit))throw Error('Unidad incompatible con el insumo');
 const s=String(raw).trim();if(!/^\d+(?:\.\d{1,3})?$/.test(s)||s.length>25)throw Error('Cantidad inválida');
 const [w,f='']=s.split('.'),m=BigInt(w)*1000n+BigInt(f.padEnd(3,'0'));
 let scaled=m;
 if(unit==='g'||unit==='ml'){if(m%1000n!==0n)throw Error('Usa gramos o mililitros enteros');scaled=m/1000n;}
 if(scaled>99999999999000n||(!zero&&scaled===0n))throw Error('Cantidad fuera de rango');
 const whole=scaled/1000n,frac=(scaled%1000n).toString().padStart(3,'0').replace(/0+$/,'');
 return whole.toString()+(frac?'.'+frac:'');
}
function renderUnitOptions(select,base){const prior=select.value;select.replaceChildren();for(const u of allowedUnits(base)){const o=document.createElement('option');o.value=u;o.textContent=({unit:'Unidad',kg:'Kilogramos (kg)',g:'Gramos (g)',L:'Litros (L)',ml:'Mililitros (ml)'})[u];select.append(o);}if(allowedUnits(base).includes(prior))select.value=prior;}
function lotStatus(expiresOn,today){if(!expiresOn)return 'Sin fecha';if(expiresOn<today)return 'Vencido';const days=(Date.parse(expiresOn+'T00:00:00Z')-Date.parse(today+'T00:00:00Z'))/86400000;return days<=7?'Vence pronto':'Disponible';}
function inventoryDay(){const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());const v=Object.fromEntries(parts.map(p=>[p.type,p.value]));return v.year+'-'+v.month+'-'+v.day;}
function createInventoryController({api,run,onChange=async()=>{}}){
 const $=id=>document.getElementById(id);let scope=null,rows=[],lots=[],branches=[],permissions={};
 const retry=requestTracker(()=>crypto.randomUUID());
 const money=n=>Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:4});
 const message=t=>{$('inventory-message').textContent=t;};
 function clear(logout=false){scope=null;rows=[];lots=[];branches=[];permissions={};for(const id of ['transfer-rows','count-rows','transfer-item','transfer-to','count-lot'])$(id).replaceChildren();$('lot-rows').replaceChildren();$('waste-lot').replaceChildren();$('waste-measure').replaceChildren();$('lot-expired').textContent='0';$('lot-soon').textContent='0';$('inventory').hidden=true;$('inventory-content').hidden=true;$('inv-rows').replaceChildren();$('mov-rows').replaceChildren();$('cost-rows').replaceChildren();$('mov-item').replaceChildren();$('min-item').replaceChildren();$('inv-search').value='';for(const f of ['ingredient-form','movement-form','minimum-form','waste-form','transfer-form','count-form']){$(f).reset();$(f).hidden=true;}message('');if(logout)retry.clear();}
 function addRow(tbody,cells,low=false){const tr=document.createElement('tr');cells.forEach((v,i)=>{const td=document.createElement('td');td.textContent=String(v);if(low&&i===cells.length-1)td.dataset.low='true';tr.append(td);});tbody.append(tr);}
 function table(){const q=$('inv-search').value.trim().toLocaleLowerCase('es');const filtered=rows.filter(r=>r.name.toLocaleLowerCase('es').includes(q));$('inv-rows').replaceChildren();for(const r of filtered)addRow($('inv-rows'),[r.name,r.quantity+' '+r.unit,r.usable+' '+r.unit,r.minimum+' '+r.unit,money(r.reference_cost),!r.active?'Inactivo':r.usable<r.minimum?'Stock bajo':r.missing?'Sin saldo':'Disponible'],r.usable<r.minimum&&r.active);if(!filtered.length)addRow($('inv-rows'),['Sin resultados','—','—','—','—','—']);$('inv-count').textContent=filtered.length+' de '+rows.length+' insumos';}
 function syncUnits(id){const item=rows.find(r=>r.id===$(id+'-item').value);if(item)renderUnitOptions($(id+'-measure'),item.unit);else $(id+'-measure').replaceChildren();}
 function options(id){const el=$(id),prior=el.value;el.replaceChildren();for(const r of rows.filter(x=>x.active)){const op=document.createElement('option');op.value=r.id;op.textContent=r.name+' ('+r.unit+')';el.append(op);}if([...el.options].some(o=>o.value===prior))el.value=prior;}
 function syncEntry(){const input=$('mov-direction').value==='in';$('entry-lot').hidden=!input;$('mov-lot-code').disabled=!input;$('mov-expiry').disabled=!input;}
 function syncWaste(){const l=lots.find(x=>x.id===$('waste-lot').value),i=l&&rows.find(r=>r.id===l.ingredient_id);if(i)renderUnitOptions($('waste-measure'),i.unit);else $('waste-measure').replaceChildren();}
 function renderLots(map){const today=inventoryDay();const order=[...lots].sort((a,b)=>(a.expires_on||'9999-12-31').localeCompare(b.expires_on||'9999-12-31')||a.received_at.localeCompare(b.received_at)||a.id.localeCompare(b.id));$('lot-rows').replaceChildren();$('waste-lot').replaceChildren();let expired=0,soon=0;
 for(const l of order){const i=map.get(l.ingredient_id),status=lotStatus(l.expires_on,today);if(status==='Vencido')expired++;if(status==='Vence pronto')soon++;addRow($('lot-rows'),[i?.name||'Insumo',l.lot_code||l.id.slice(0,8),l.quantity+' '+(i?.unit||''),l.expires_on||'No registrada',status],status==='Vencido'||status==='Vence pronto');if(i?.active){const o=document.createElement('option');o.value=l.id;o.textContent=i.name+' · '+(l.lot_code||l.id.slice(0,8))+' · '+l.quantity+' '+i.unit+' · '+status;$('waste-lot').append(o);}}
 if(!order.length)addRow($('lot-rows'),['Sin lotes','—','—','—','—']);$('lot-expired').textContent=expired;$('lot-soon').textContent=soon;syncWaste();}
 function syncCount(){const l=lots.find(x=>x.id===$('count-lot').value);$('count-expected').textContent=l?'Saldo registrado: '+l.quantity+' '+(rows.find(x=>x.id===l.ingredient_id)?.unit||''):'Selecciona un lote';$('count-qty').value='';}
 function renderAdjustments(map,transfers,counts){options('transfer-item');syncUnits('transfer');$('transfer-to').replaceChildren();for(const b of branches.filter(b=>b.active&&b.id!==scope.branch)){const o=document.createElement('option');o.value=b.id;o.textContent=b.name;$('transfer-to').append(o);}
 $('count-lot').replaceChildren();for(const l of lots.filter(l=>map.get(l.ingredient_id)?.active)){const o=document.createElement('option');o.value=l.id;o.textContent=map.get(l.ingredient_id).name+' · '+(l.lot_code||l.id.slice(0,8))+' · '+l.quantity+' '+map.get(l.ingredient_id).unit;$('count-lot').append(o);}syncCount();
 $('transfer-rows').replaceChildren();$('count-rows').replaceChildren();const branchName=id=>branches.find(b=>b.id===id)?.name||id;for(const t of transfers.filter(t=>t.from_branch===scope.branch||t.to_branch===scope.branch))addRow($('transfer-rows'),[new Date(t.created_at).toLocaleString('es-PE',{timeZone:'America/Lima'}),map.get(t.ingredient_id)?.name||'Insumo',branchName(t.from_branch),branchName(t.to_branch),t.quantity+' '+(map.get(t.ingredient_id)?.unit||''),t.reason]);if(!$('transfer-rows').children.length)addRow($('transfer-rows'),['Sin traslados','—','—','—','—','—']);
 for(const c of counts)addRow($('count-rows'),[new Date(c.created_at).toLocaleString('es-PE',{timeZone:'America/Lima'}),map.get(c.ingredient_id)?.name||'Insumo',c.lot_id.slice(0,8),c.expected_quantity,c.counted_quantity,c.reason]);if(!counts.length)addRow($('count-rows'),['Sin conteos','—','—','—','—','—']);}
 async function refresh(){
 if(!scope)return;
 $('inventory-content').hidden=true;
 try{
 const {bakery,branch,role}=scope;
 const [ingredients,balances,movements,subs,costs,usable,lotRows,branchRows,transfers,counts]=await Promise.all([collectPages(c=>api.ingredients(bakery,c),'id'),collectPages(c=>api.balances(bakery,branch,c),'ingredient_id'),api.lotMovements(bakery,branch),api.subscription(bakery),api.costHistory(bakery,branch),collectPages(c=>api.usableBalances(bakery,branch,c),'ingredient_id'),collectPages(c=>api.lots(bakery,branch,c),'id'),api.branches(bakery),api.transfers(bakery),api.counts(bakery,branch)]);
 if(!Array.isArray(movements)||!Array.isArray(subs)||!Array.isArray(costs))throw Error('Invalid response');
 const usableMap=new Map(usable.map(r=>[r.ingredient_id,Number(r.quantity)]));lots=lotRows;branches=branchRows;rows=inventoryRows(ingredients,balances).map(r=>({...r,usable:usableMap.get(r.id)||0})).sort((a,b)=>a.name.localeCompare(b.name,'es'));
 permissions=modulePermissions(scope,subs[0],'inventory');const active=rows.filter(r=>r.active);
 $('inv-total').textContent=active.length;$('inv-low').textContent=active.filter(r=>r.usable<r.minimum).length;$('inv-missing').textContent=active.filter(r=>r.missing).length;
 table();options('mov-item');options('min-item');syncUnits('mov');syncUnits('min');$('mov-rows').replaceChildren();
 const map=new Map(rows.map(r=>[r.id,r]));renderLots(map);renderAdjustments(map,transfers,counts);for(const m of movements){const i=map.get(m.ingredient_id);addRow($('mov-rows'),[new Date(m.created_at).toLocaleString('es-PE',{timeZone:'America/Lima'}),i?.name||m.ingredient_id,({waste:'Merma',transfer:'Traslado',count:'Conciliación'}[m.movement_category]||(m.direction==='in'?'Entrada':'Salida')),m.quantity+' '+(i?.unit||''),m.reason]);}
 $('cost-rows').replaceChildren();for(const c of costs){const i=map.get(c.ingredient_id);addRow($('cost-rows'),[new Date(c.created_at).toLocaleString('es-PE',{timeZone:'America/Lima'}),i?.name||'Insumo',c.purchased_quantity+' '+(i?.unit||''),money(c.purchased_unit_cost),money(c.previous_cost),money(c.new_cost)]);}if(!costs.length)addRow($('cost-rows'),['Sin compras','—','—','—','—','—']);
 if(!movements.length)addRow($('mov-rows'),['Sin movimientos','—','—','—','—']);
 $('ingredient-form').hidden=!permissions.manager;$('minimum-form').hidden=!permissions.manager||!active.length;$('movement-form').hidden=!permissions.movement||!active.length;$('waste-form').hidden=!permissions.manager||!lots.some(l=>map.get(l.ingredient_id)?.active);$('transfer-form').hidden=!permissions.manager||!active.length||!branches.some(b=>b.active&&b.id!==branch);$('count-form').hidden=!permissions.manager||!lots.some(l=>map.get(l.ingredient_id)?.active);syncEntry();
 $('inventory-content').hidden=false;message(permissions.active?'':'Suscripción inactiva o vencida: acceso de consulta.');
 }catch(e){rows=[];permissions={};$('inv-rows').replaceChildren();$('mov-rows').replaceChildren();message('No se pudo cargar el almacén. Actualiza para volver a consultar.');if(!api.hasSession())throw e;}
 }
 async function open(next){scope=next;$('inventory').hidden=false;$('inventory-scope').textContent=next.label;await refresh();}
 async function execute(action,success){
 try{await action();}catch(e){message('Operación no confirmada. Revisa existencias, permisos y suscripción. Si fue un movimiento, reintenta con los mismos datos en esta sesión.');if(!api.hasSession())throw e;return;}
 await refresh();if(!$('inventory-content').hidden)message(success);await onChange();
 }
 $('inv-search').addEventListener('input',table);$('mov-direction').addEventListener('change',syncEntry);$('waste-lot').addEventListener('change',syncWaste);$('count-lot').addEventListener('change',syncCount);for(const id of ['mov','min','transfer'])$(id+'-item').addEventListener('change',()=>syncUnits(id));
 $('inventory-reload').addEventListener('click',()=>run(refresh));
 $('ingredient-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.manager)return;const name=$('ing-name').value.trim();if(!name){message('Escribe el nombre del insumo.');return;}let cost;try{cost=decimal($('ing-cost').value,4,9999999999,true);}catch{message('Costo inválido.');return;}await execute(async()=>{await api.addIngredient(scope.bakery,name,$('ing-unit').value,cost);$('ingredient-form').reset();},'Insumo registrado.');});});
 $('movement-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.movement)return;let qty;try{qty=Number(baseQuantity($('mov-qty').value,$('mov-measure').value,rows.find(r=>r.id===$('mov-item').value)?.unit));}catch{message('Cantidad inválida.');return;}const item=$('mov-item').value,dir=$('mov-direction').value,reason=$('mov-reason').value.trim();if(!item||!reason){message('Selecciona insumo y motivo.');return;}
 const lotCode=dir==='in'?$('mov-lot-code').value.trim()||null:null,expiry=dir==='in'?$('mov-expiry').value||null:null;const payload=[scope.bakery,scope.branch,item,dir,qty,reason,lotCode,expiry];
 await execute(async()=>{const req=retry.id(payload);await api.lotMovement(scope.bakery,scope.branch,item,req,dir,qty,reason,lotCode,expiry,null);$('mov-lot-code').value='';$('mov-expiry').value='';retry.complete(payload);$('mov-qty').value='';$('mov-reason').value='';},'Movimiento confirmado.');});});
 $('waste-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.manager)return;const l=lots.find(x=>x.id===$('waste-lot').value),i=l&&rows.find(x=>x.id===l.ingredient_id);if(!l||!i)return;let qty;try{qty=Number(baseQuantity($('waste-qty').value,$('waste-measure').value,i.unit));if(qty>Number(l.quantity))throw Error();}catch{message('Cantidad de merma inválida o superior al lote.');return;}const reason=$('waste-reason').value.trim();if(!reason)return;const payload=[scope.bakery,scope.branch,l.id,qty,reason,'waste'];await execute(async()=>{await api.lotMovement(scope.bakery,scope.branch,i.id,retry.id(payload),'out',qty,reason,null,null,l.id);retry.complete(payload);$('waste-qty').value='';$('waste-reason').value='';},'Merma registrada.');});});
 $('transfer-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.manager)return;const item=$('transfer-item').value,to=$('transfer-to').value,reason=$('transfer-reason').value.trim();let qty;try{qty=Number(baseQuantity($('transfer-qty').value,$('transfer-measure').value,rows.find(r=>r.id===item)?.unit));}catch{message('Cantidad inválida.');return;}if(!to||!reason||!confirm('¿Confirmar traslado de insumos?'))return;const payload=['transfer',scope.bakery,scope.branch,to,item,qty,reason];await execute(async()=>{await api.transferInventory(scope.bakery,scope.branch,to,item,retry.id(payload),qty,reason);retry.complete(payload);$('transfer-qty').value='';$('transfer-reason').value='';},'Traslado confirmado en ambas sucursales.');});});
 $('count-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.manager)return;const l=lots.find(l=>l.id===$('count-lot').value),reason=$('count-reason').value.trim();if(!l||!reason)return;let qty;try{qty=decimal($('count-qty').value,3,99999999999,true);}catch{message('Conteo inválido.');return;}if(!confirm('¿Conciliar el saldo físico indicado?'))return;const expected=Number(l.quantity),payload=['count',scope.bakery,scope.branch,l.id,expected,qty,reason];await execute(async()=>{await api.reconcileInventory(scope.bakery,scope.branch,l.id,retry.id(payload),expected,qty,reason);retry.complete(payload);$('count-reason').value='';},'Conteo registrado.');});});
 $('minimum-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.manager)return;let qty;try{qty=Number(baseQuantity($('min-qty').value,$('min-measure').value,rows.find(r=>r.id===$('min-item').value)?.unit,true));}catch{message('Mínimo inválido.');return;}const item=$('min-item').value;if(!item)return;await execute(async()=>{await api.minimum(scope.bakery,scope.branch,item,qty);$('min-qty').value='';},'Mínimo actualizado.');});});
 return {open,clear,refresh};
}
if(typeof module!=='undefined')module.exports={collectPages,inventoryRows,inventoryPermissions,decimal,requestTracker,allowedUnits,baseQuantity,lotStatus,modulePermissions,employeePermissionLabels};
