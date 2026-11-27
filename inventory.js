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
function decimal(raw,precision,max,allowZero=false){
 const s=String(raw).trim();if(!new RegExp('^\\d+(?:\\.\\d{1,'+precision+'})?$').test(s))throw Error('Cantidad inválida');
 const n=Number(s);if(!Number.isFinite(n)||n>max||n<0||(!allowZero&&n===0))throw Error('Cantidad fuera de rango');return n;
}
function requestTracker(makeId){
 const pending=new Map();
 return {id(payload){const key=JSON.stringify(payload);if(!pending.has(key))pending.set(key,makeId());return pending.get(key);},
 complete(payload){pending.delete(JSON.stringify(payload));},clear(){pending.clear();}};
}
function createInventoryController({api,run}){
 const $=id=>document.getElementById(id);let scope=null,rows=[],permissions={};
 const retry=requestTracker(()=>crypto.randomUUID());
 const money=n=>Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:4});
 const message=t=>{$('inventory-message').textContent=t;};
 function clear(logout=false){scope=null;rows=[];permissions={};$('inventory').hidden=true;$('inventory-content').hidden=true;$('inv-rows').replaceChildren();$('mov-rows').replaceChildren();$('mov-item').replaceChildren();$('min-item').replaceChildren();$('inv-search').value='';for(const f of ['ingredient-form','movement-form','minimum-form']){$(f).reset();$(f).hidden=true;}message('');if(logout)retry.clear();}
 function addRow(tbody,cells,low=false){const tr=document.createElement('tr');cells.forEach((v,i)=>{const td=document.createElement('td');td.textContent=String(v);if(low&&i===cells.length-1)td.dataset.low='true';tr.append(td);});tbody.append(tr);}
 function table(){const q=$('inv-search').value.trim().toLocaleLowerCase('es');const filtered=rows.filter(r=>r.name.toLocaleLowerCase('es').includes(q));$('inv-rows').replaceChildren();for(const r of filtered)addRow($('inv-rows'),[r.name,r.quantity+' '+r.unit,r.minimum+' '+r.unit,money(r.reference_cost),!r.active?'Inactivo':r.low?'Stock bajo':r.missing?'Sin saldo':'Disponible'],r.low&&r.active);if(!filtered.length)addRow($('inv-rows'),['Sin resultados','—','—','—','—']);$('inv-count').textContent=filtered.length+' de '+rows.length+' insumos';}
 function options(id){const el=$(id),prior=el.value;el.replaceChildren();for(const r of rows.filter(x=>x.active)){const op=document.createElement('option');op.value=r.id;op.textContent=r.name+' ('+r.unit+')';el.append(op);}if([...el.options].some(o=>o.value===prior))el.value=prior;}
 async function refresh(){
 if(!scope)return;
 $('inventory-content').hidden=true;
 try{
 const {bakery,branch,role}=scope;
 const [ingredients,balances,movements,subs]=await Promise.all([collectPages(c=>api.ingredients(bakery,c),'id'),collectPages(c=>api.balances(bakery,branch,c),'ingredient_id'),api.movements(bakery,branch),api.subscription(bakery)]);
 if(!Array.isArray(movements)||!Array.isArray(subs))throw Error('Invalid response');
 rows=inventoryRows(ingredients,balances).sort((a,b)=>a.name.localeCompare(b.name,'es'));
 permissions=inventoryPermissions(role,subs[0]);const active=rows.filter(r=>r.active);
 $('inv-total').textContent=active.length;$('inv-low').textContent=active.filter(r=>r.low).length;$('inv-missing').textContent=active.filter(r=>r.missing).length;
 table();options('mov-item');options('min-item');$('mov-rows').replaceChildren();
 const map=new Map(rows.map(r=>[r.id,r]));for(const m of movements){const i=map.get(m.ingredient_id);addRow($('mov-rows'),[new Date(m.created_at).toLocaleString('es-PE',{timeZone:'America/Lima'}),i?.name||m.ingredient_id,m.direction==='in'?'Entrada':'Salida',m.quantity+' '+(i?.unit||''),m.reason]);}
 if(!movements.length)addRow($('mov-rows'),['Sin movimientos','—','—','—','—']);
 $('ingredient-form').hidden=!permissions.manager;$('minimum-form').hidden=!permissions.manager||!active.length;$('movement-form').hidden=!permissions.movement||!active.length;
 $('inventory-content').hidden=false;message(permissions.active?'':'Suscripción inactiva o vencida: acceso de consulta.');
 }catch(e){rows=[];permissions={};$('inv-rows').replaceChildren();$('mov-rows').replaceChildren();message('No se pudo cargar el almacén. Actualiza para volver a consultar.');if(!api.hasSession())throw e;}
 }
 async function open(next){scope=next;$('inventory').hidden=false;$('inventory-scope').textContent=next.label;await refresh();}
 async function execute(action,success){
 try{await action();}catch(e){message('Operación no confirmada. Revisa existencias, permisos y suscripción. Si fue un movimiento, reintenta con los mismos datos en esta sesión.');if(!api.hasSession())throw e;return;}
 await refresh();if(!$('inventory-content').hidden)message(success);
 }
 $('inv-search').addEventListener('input',table);
 $('inventory-reload').addEventListener('click',()=>run(refresh));
 $('ingredient-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.manager)return;const name=$('ing-name').value.trim();if(!name){message('Escribe el nombre del insumo.');return;}let cost;try{cost=decimal($('ing-cost').value,4,9999999999,true);}catch{message('Costo inválido.');return;}await execute(async()=>{await api.addIngredient(scope.bakery,name,$('ing-unit').value,cost);$('ingredient-form').reset();},'Insumo registrado.');});});
 $('movement-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.movement)return;let qty;try{qty=decimal($('mov-qty').value,3,99999999999);}catch{message('Cantidad inválida.');return;}const item=$('mov-item').value,dir=$('mov-direction').value,reason=$('mov-reason').value.trim();if(!item||!reason){message('Selecciona insumo y motivo.');return;}
 const payload=[scope.bakery,scope.branch,item,dir,qty,reason];
 await execute(async()=>{const req=retry.id(payload);await api.movement(scope.bakery,scope.branch,item,req,dir,qty,reason);retry.complete(payload);$('mov-qty').value='';$('mov-reason').value='';},'Movimiento confirmado.');});});
 $('minimum-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!permissions.manager)return;let qty;try{qty=decimal($('min-qty').value,3,99999999999,true);}catch{message('Mínimo inválido.');return;}const item=$('min-item').value;if(!item)return;await execute(async()=>{await api.minimum(scope.bakery,scope.branch,item,qty);$('min-qty').value='';},'Mínimo actualizado.');});});
 return {open,clear};
}
if(typeof module!=='undefined')module.exports={collectPages,inventoryRows,inventoryPermissions,decimal,requestTracker};
