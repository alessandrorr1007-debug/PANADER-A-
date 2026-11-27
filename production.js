'use strict';
// Exact scaled integer arithmetic mirrors the SQL ceil(qty * units / yield * 1000) rule.
function milliUnits(raw){
 const s=String(raw);if(!/^\d+(?:\.\d{1,3})?$/.test(s))throw Error('Invalid base quantity');
 const [whole,fraction='']=s.split('.');return BigInt(whole)*1000n+BigInt(fraction.padEnd(3,'0'));
}
function previewProduction(recipe,items,ingredients,balances,units){
 if(!recipe||!Number.isInteger(units)||units<1||units>1000000||!Number.isInteger(Number(recipe.yield_units))||Number(recipe.yield_units)<1)throw Error('Invalid production');
 const ingredientsById=new Map(ingredients.map(i=>[i.id,i])),stock=new Map(balances.map(b=>[b.ingredient_id,milliUnits(b.quantity)]));
 const yieldUnits=BigInt(recipe.yield_units);let total=0;
 const lines=items.map(line=>{const i=ingredientsById.get(line.ingredient_id);const amount=milliUnits(line.quantity);if(amount<=0n)throw Error('Invalid recipe line');const needed=(amount*BigInt(units)+yieldUnits-1n)/yieldUnits;const available=stock.get(line.ingredient_id)||0n;const quantity=Number(needed)/1000;const cost=quantity*Number(i?.reference_cost||0);total+=cost;return {name:i?.name||'Insumo no disponible',unit:i?.unit||'',quantity,available:Number(available)/1000,ready:!!i?.active&&needed<=available&&needed<=99999999999000n};});
 return {lines,total,unitCost:total/units,ready:lines.length>0&&lines.every(l=>l.ready)};
}
function validateRecipeDraft(name,yieldRaw,lines){
 name=String(name).trim();const units=Number(yieldRaw);if(!name||name.length>120||!/^\d+$/.test(String(yieldRaw))||!Number.isInteger(units)||units<1||units>1000000||!Array.isArray(lines)||lines.length<1||lines.length>100)throw Error('Completa nombre, rendimiento e ingredientes.');
 const ids=new Set();const items=lines.map(l=>{if(!l.ingredient_id||ids.has(l.ingredient_id))throw Error('Selecciona ingredientes diferentes.');ids.add(l.ingredient_id);const m=milliUnits(l.quantity);if(m<=0n||m>99999999999000n)throw Error('Cantidad inválida.');return {ingredient_id:l.ingredient_id,quantity:Number(m)/1000};});
 return {name,units,items};
}
function createProductionController({api,run,onChange=async()=>{}}){
 const $=id=>document.getElementById(id);let scope=null,recipes=[],ingredients=[],balances=[],items=[],selected=null,permissions={},preview=null,loaded=false;
 const tracker=requestTracker(()=>crypto.randomUUID());
 const message=t=>{$('production-message').textContent=t;};
 const money=n=>'S/ '+Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:4});
 const label=r=>r.name+' · v'+r.version;
 function row(id,cells){const tr=document.createElement('tr');for(const v of cells){const td=document.createElement('td');td.textContent=String(v);tr.append(td);};$(id).append(tr);}
 function syncControls(){const enabled=loaded&&permissions.movement&&preview?.ready&&$('batch-confirm').checked;$('batch-form').querySelector('button').disabled=!enabled;}
 function clear(logout=false){scope=null;recipes=[];ingredients=[];balances=[];items=[];selected=null;permissions={};preview=null;loaded=false;$('production-area').hidden=true;$('production-content').hidden=true;$('recipe-select').replaceChildren();$('recipe-lines').replaceChildren();$('batch-preview').replaceChildren();$('batch-rows').replaceChildren();$('recipe-form').reset();$('batch-form').reset();$('batch-units').value='100';$('recipe-details').textContent='';$('batch-ready').textContent='';$('batch-cost').textContent='—';$('batch-unit-cost').textContent='—';message('');if(logout)tracker.clear();}
 function addLine(){if($('recipe-lines').children.length>=100)return;const active=ingredients.filter(i=>i.active);if(!active.length)return;const wrap=document.createElement('div');wrap.className='recipe-line';const lab=document.createElement('label');lab.textContent='Insumo';const sel=document.createElement('select');sel.required=true;for(const i of active){const op=document.createElement('option');op.value=i.id;op.textContent=i.name+' ('+i.unit+')';sel.append(op);}lab.append(sel);const qlab=document.createElement('label');qlab.textContent='Cantidad';const q=document.createElement('input');q.type='number';q.required=true;q.min='0.001';q.max='99999999999';q.step='0.001';qlab.append(q);const rm=document.createElement('button');rm.type='button';rm.textContent='×';rm.setAttribute('aria-label','Quitar ingrediente');rm.addEventListener('click',()=>wrap.remove());wrap.append(lab,qlab,rm);$('recipe-lines').append(wrap);}
 function renderPreview(){preview=null;$('batch-preview').replaceChildren();$('batch-confirm').checked=false;try{const raw=$('batch-units').value;if(!/^\d+$/.test(raw))throw Error();preview=previewProduction(selected,items,ingredients,balances,Number(raw));for(const l of preview.lines)row('batch-preview',[l.name,l.quantity+' '+l.unit,l.available+' '+l.unit,l.ready?'Disponible':'Insuficiente / inactivo']);$('batch-cost').textContent=money(preview.total);$('batch-unit-cost').textContent=money(preview.unitCost);$('batch-ready').textContent=preview.ready?'Stock suficiente según la última consulta.':'No hay stock suficiente o hay insumos inactivos.';$('batch-ready').dataset.ready=String(preview.ready);}catch{$('batch-cost').textContent='—';$('batch-unit-cost').textContent='—';$('batch-ready').textContent='Selecciona una receta y un rendimiento válido.';$('batch-ready').dataset.ready='false';}syncControls();}
 async function selectRecipe(){selected=null;items=[];renderPreview();const r=recipes.find(x=>x.id===$('recipe-select').value);if(!scope||!r){$('recipe-details').textContent='No hay recetas registradas.';return;}const lines=await collectPages(c=>api.recipeItems(scope.bakery,r.id,c),'ingredient_id',100);selected=r;items=lines;$('recipe-details').textContent='Rendimiento base: '+r.yield_units+' unidades · '+lines.length+' ingredientes';renderPreview();}
 async function refresh(){if(!scope)return;loaded=false;preview=null;$('production-content').hidden=true;const prior=$('recipe-select').value;try{
 const {bakery,branch,role}=scope;
 const [rs,ins,bs,history,subs]=await Promise.all([collectPages(c=>api.recipes(bakery,c),'id'),collectPages(c=>api.ingredients(bakery,c),'id'),collectPages(c=>api.balances(bakery,branch,c),'ingredient_id'),api.batches(bakery,branch),api.subscription(bakery)]);
 if(!Array.isArray(history)||!Array.isArray(subs))throw Error('Invalid response');
 recipes=rs.sort((a,b)=>a.name.localeCompare(b.name,'es')||Number(b.version)-Number(a.version));ingredients=ins;balances=bs;permissions=inventoryPermissions(role,subs[0]);
 $('recipe-count').textContent=recipes.length;$('recipe-usable').textContent=new Set(recipes.map(r=>r.name.trim().toLocaleLowerCase('es'))).size;$('batch-count').textContent=history.length;
 $('recipe-select').replaceChildren();for(const r of recipes){const op=document.createElement('option');op.value=r.id;op.textContent=label(r);$('recipe-select').append(op);}if(recipes.some(r=>r.id===prior))$('recipe-select').value=prior;
 $('batch-rows').replaceChildren();const byId=new Map(recipes.map(r=>[r.id,r]));for(const b of history)row('batch-rows',[new Date(b.created_at).toLocaleString('es-PE',{timeZone:'America/Lima'}),byId.has(b.recipe_id)?label(byId.get(b.recipe_id)):b.recipe_id,b.output_units,money(b.reference_cost),b.id.slice(0,8)]);if(!history.length)row('batch-rows',['Sin lotes','—','—','—','—']);
 $('recipe-form').hidden=!permissions.manager||!ingredients.some(i=>i.active);$('batch-form').hidden=!permissions.movement||!recipes.length;
 $('recipe-lines').replaceChildren();if(!$('recipe-form').hidden)addLine();await selectRecipe();loaded=true;$('production-content').hidden=false;syncControls();message(permissions.active?'':'Suscripción vencida o inactiva: solo consulta.');
 }catch(e){loaded=false;preview=null;selected=null;items=[];message('No se pudo cargar recetas y producción. Actualiza para volver a consultar.');if(!api.hasSession())throw e;}}
 async function open(next){scope=next;$('production-area').hidden=false;$('production-scope').textContent=next.label;await refresh();}
 $('production-reload').addEventListener('click',()=>run(refresh));
 $('recipe-add-line').addEventListener('click',addLine);
 $('recipe-select').addEventListener('change',()=>run(async()=>{try{await selectRecipe();}catch(e){selected=null;items=[];renderPreview();message('No se pudo cargar la receta.');if(!api.hasSession())throw e;}}));
 $('batch-units').addEventListener('input',renderPreview);$('batch-confirm').addEventListener('change',syncControls);
 $('recipe-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!loaded||!permissions.manager)return;let draft;try{draft=validateRecipeDraft($('recipe-name').value,$('recipe-yield').value,[...$('recipe-lines').children].map(el=>({ingredient_id:el.querySelector('select').value,quantity:el.querySelector('input').value})));}catch(e){message(e.message);return;}
 try{await api.createRecipe(scope.bakery,draft.name,draft.units,draft.items);}catch(e){message('Versión no confirmada. Consulta las versiones antes de repetir: el alta no tiene identificador de reintento.');if(!api.hasSession())throw e;return;}
 $('recipe-form').reset();await refresh();if(loaded)message('Versión registrada.');});});
 $('batch-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!loaded||!permissions.movement||!preview?.ready||!selected||!$('batch-confirm').checked)return;
 const units=Number($('batch-units').value),payload=[scope.bakery,scope.branch,selected.id,units];
 try{await api.completeBatch(scope.bakery,scope.branch,selected.id,tracker.id(payload),units);tracker.complete(payload);}catch(e){message('Lote no confirmado. Verifica el historial; si reintentas, conserva los mismos datos durante esta sesión.');if(!api.hasSession())throw e;return;}
 $('batch-confirm').checked=false;await refresh();if(loaded)message('Lote confirmado. Se actualizó el consumo de insumos.');await onChange();});});
 return {open,clear,refresh,syncControls};
}
if(typeof module!=='undefined')module.exports={milliUnits,previewProduction,validateRecipeDraft};
