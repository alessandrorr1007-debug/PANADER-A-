'use strict';
function scaled(raw,precision,max,zero=false){
 const s=String(raw).trim();if(!new RegExp('^\\d+(?:\\.\\d{1,'+precision+'})?$').test(s))throw Error('Importe o cantidad inválidos.');
 const [w,f='']=s.split('.');const n=BigInt(w)*10n**BigInt(precision)+BigInt(f.padEnd(precision,'0'));
 if(n>max||(!zero&&n===0n))throw Error('Cantidad o importe fuera de rango.');return n;
}
function centsText(n){const sign=n<0n?'-':'';const a=n<0n?-n:n;return sign+(a/100n).toString()+'.'+(a%100n).toString().padStart(2,'0');}
function purchaseDraft(lines,ingredients){
 if(!lines.length||lines.length>100)throw Error('Añade entre 1 y 100 insumos.');
 const ids=new Set();let cents=0n;
 const items=lines.map(l=>{if(ids.has(l.id)||!ingredients.some(i=>i.id===l.id&&i.active))throw Error('Selecciona insumos activos diferentes.');ids.add(l.id);
 const q=scaled(l.quantity,3,99999999999000n),c=scaled(l.cost,4,99999999990000n,true);
 cents+=(q*c+50000n)/100000n;const item={ingredient_id:l.id,quantity:Number(q)/1000,unit_cost:Number(c)/10000};if(l.lotCode){if(l.lotCode.length>80)throw Error('Código de lote demasiado largo');item.lot_code=l.lotCode;}if(l.expiry){if(!/^\d{4}-\d{2}-\d{2}$/.test(l.expiry))throw Error('Fecha inválida');item.expires_on=l.expiry;}return item;});
 return {items,cents};
}
function saleDraft(lines,finished){
 if(!lines.length||lines.length>100)throw Error('Añade entre 1 y 100 lotes.');
 const ids=new Set();let cents=0n;
 const items=lines.map(l=>{const p=finished.find(x=>x.batch_id===l.id);if(!p||ids.has(l.id)||p.price==null)throw Error('Selecciona lotes distintos con precio configurado.');ids.add(l.id);
 if(!/^\d+$/.test(String(l.quantity)))throw Error('Las unidades deben ser enteras.');
 const u=Number(l.quantity);if(!Number.isSafeInteger(u)||u<1||u>1000000||u>Number(p.available_units))throw Error('Unidades inválidas o stock insuficiente.');
 const price=scaled(p.price,2,999999999999n);cents+=BigInt(u)*price;return {batch_id:l.id,units:u,unit_price:Number(price)/100};});
 return {items,cents};
}
function createCommerceController({api,run,onPurchase=async()=>{},onChange=async()=>{}}){
 const $=id=>document.getElementById(id),tracker=requestTracker(()=>crypto.randomUUID());let scope=null,loaded=false,permissions={},suppliers=[],ingredients=[],recipes=[],finished=[],catalog=[],shift=null;
 const catalogOrders=createCatalogOrdersController({api,run,reload:async()=>{await refresh();await onChange();}});
 const msg=t=>{$('commerce-message').textContent=t;};
 const money=n=>'S/ '+Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:2});
 const date=n=>new Date(n).toLocaleString('es-PE',{timeZone:'America/Lima'});
 const paymentNames={cash:'Efectivo',wallet:'Billetera digital',card:'Tarjeta',transfer:'Transferencia'};
 const forms=['supplier-form','price-form','cash-open-form','cash-close-form','purchase-form','sale-form'];
 const tables=['finished-rows','purchase-history','sale-history'];
 function clear(logout=false){scope=null;loaded=false;permissions={};suppliers=[];ingredients=[];recipes=[];finished=[];catalog=[];shift=null;catalogOrders.clear(logout);$('pos-products').replaceChildren();$('pos-search').value='';$('commerce-area').hidden=true;$('commerce-content').hidden=true;forms.forEach(f=>{$(f).reset();$(f).hidden=true;});[...tables,'purchase-lines','sale-lines','price-recipe','purchase-supplier'].forEach(id=>$(id).replaceChildren());msg('');if(logout)tracker.clear();}
 function row(id,cells){const tr=document.createElement('tr');cells.forEach(v=>{const td=document.createElement('td');td.textContent=String(v);tr.append(td);});$(id).append(tr);}
 function options(el,values){el.replaceChildren();for(const [v,t] of values){const o=document.createElement('option');o.value=v;o.textContent=t;el.append(o);}}
 function field(text,el){const l=document.createElement('label');l.textContent=text;l.append(el);return l;}
 function num(min,step,max){const i=document.createElement('input');i.type='number';i.min=min;i.step=step;i.max=max;i.required=true;return i;}
 const saleable=()=>finished.filter(r=>Number(r.available_units)>0&&r.price!=null);
 function addLine(kind,batchId=null,initial=null){const isPurchase=kind==='purchase',box=$(kind+'-lines');if(box.children.length>=100)return;const list=isPurchase?ingredients.filter(i=>i.active).map(i=>[i.id,i.name+' ('+i.unit+')']):saleable().map(i=>[i.batch_id,i.label+' · '+i.batch_id.slice(0,8)+' · '+i.available_units+' disp. · '+money(i.price)]);if(!list.length)return;
 const line=document.createElement('div');line.className='commerce-line'+(isPurchase?' purchase-line':'');const sel=document.createElement('select');sel.required=true;options(sel,list);
 if(batchId&&list.some(x=>x[0]===batchId))sel.value=batchId;
 const qty=num(isPurchase?'0.001':'1',isPurchase?'0.001':'1',isPurchase?'99999999999':'1000000');
 if(initial!==null)qty.value=String(initial);line.append(field(isPurchase?'Insumo':'Lote',sel),field('Cantidad',qty));if(isPurchase){const unit=document.createElement('select');unit.className='measure-select';const cost=num('0','0.0001','9999999999');const costField=field('Costo por unidad base',cost);const sync=()=>{const i=ingredients.find(i=>i.id===sel.value);renderUnitOptions(unit,i.unit);costField.firstChild.textContent='Costo por '+i.unit+' (S/)';};sel.addEventListener('change',sync);sync();const lot=document.createElement('input');lot.type='text';lot.maxLength=80;lot.className='purchase-lot';const expiry=document.createElement('input');expiry.type='date';expiry.className='purchase-expiry';line.append(field('Unidad de cantidad',unit),costField,field('Lote (opcional)',lot),field('Vence (opcional)',expiry));}
 const remove=document.createElement('button');remove.type='button';remove.textContent='×';remove.setAttribute('aria-label','Quitar línea');remove.addEventListener('click',()=>{line.remove();preview(kind);});line.append(remove);line.addEventListener('input',()=>preview(kind));line.addEventListener('change',()=>preview(kind));box.append(line);preview(kind);return line;}
 function getLines(kind){return [...$(kind+'-lines').children].map(el=>{const inputs=el.querySelectorAll('input');return {id:el.querySelector('select').value,quantity:kind==='purchase'?baseQuantity(inputs[0].value,el.querySelector('.measure-select').value,ingredients.find(i=>i.id===el.querySelector('select').value)?.unit):inputs[0].value,cost:inputs[1]?.value,lotCode:el.querySelector('.purchase-lot')?.value.trim(),expiry:el.querySelector('.purchase-expiry')?.value};});}
 function draft(kind){return kind==='purchase'?purchaseDraft(getLines(kind),ingredients):saleDraft(getLines(kind),finished);}
 function preview(kind){$(kind+'-confirm').checked=false;try{$(kind+'-total').textContent='Total: S/ '+centsText(draft(kind).cents);}catch(e){$(kind+'-total').textContent='Total: — · '+e.message;}}
 function addPosProduct(recipe){if(!loaded||!permissions.movement||!shift)return;const candidates=saleable().filter(f=>f.recipe_id===recipe);const lines=[...$('sale-lines').children];for(const f of candidates){const el=lines.find(l=>l.querySelector('select').value===f.batch_id);if(el){const input=el.querySelector('input'),q=Number(input.value||0);if(Number.isInteger(q)&&q<Number(f.available_units)){input.value=String(q+1);preview('sale');return;}}else{addLine('sale',f.batch_id,1);return;}}msg('No queda stock disponible para añadir.');
 }
 function renderPos(){const q=$('pos-search').value.trim().toLocaleLowerCase('es');$('pos-products').replaceChildren();for(const p of catalog.filter(p=>p.active&&p.unit_price!=null&&(p.display_name+' '+p.category+' '+(p.sku||'')).toLocaleLowerCase('es').includes(q))){const units=saleable().filter(f=>f.recipe_id===p.recipe_id).reduce((n,f)=>n+Number(f.available_units),0);const btn=document.createElement('button');btn.type='button';btn.className='pos-product';btn.disabled=!units;const name=document.createElement('strong'),meta=document.createElement('small'),price=document.createElement('b');name.textContent=p.display_name;meta.textContent=p.category+' · '+units+' disponibles';price.textContent=money(p.unit_price);btn.append(name,meta,price);btn.addEventListener('click',()=>addPosProduct(p.recipe_id));$('pos-products').append(btn);}if(!$('pos-products').children.length){const p=document.createElement('p');p.textContent='No hay productos activos con precio para esta búsqueda.';$('pos-products').append(p);}}
 async function refresh(){if(!scope)return;loaded=false;$('commerce-content').hidden=true;try{
 const {bakery:b,branch:r,role}=scope;
 const [ss,ii,rr,pp,ff,cc,ph,sh,sub,products]=await Promise.all([collectPages(c=>api.suppliers(b,c),'id'),collectPages(c=>api.ingredients(b,c),'id'),collectPages(c=>api.recipes(b,c),'id'),collectPages(c=>api.prices(b,c),'recipe_id'),collectPages(c=>api.finished(b,r,c),'batch_id'),api.cashOpen(b,r),api.purchases(b,r),api.sales(b,r),api.subscription(b),collectPages(c=>api.catalogProducts(b,c),'recipe_id')]);
 if(![cc,ph,sh,sub].every(Array.isArray)||cc.length>1)throw Error('Invalid response');
 suppliers=ss;ingredients=ii;recipes=rr;catalog=products;permissions=modulePermissions(scope,sub[0],'purchases','sales');shift=cc[0]||null;const manager=permissions.has('cash');
 const recipeById=new Map(rr.map(x=>[x.id,x])),priceById=new Map(pp.map(x=>[x.recipe_id,x.unit_price])),supplierById=new Map(ss.map(x=>[x.id,x.name]));
 const byProduct=new Map(catalog.map(p=>[p.recipe_id,p]));finished=ff.map(x=>{const recipe=recipeById.get(x.recipe_id),p=byProduct.get(x.recipe_id);return {...x,label:p?.display_name||(recipe?recipe.name+' · v'+recipe.version:x.recipe_id),price:p?.active===false?null:priceById.get(x.recipe_id)??null};});
 $('com-suppliers').textContent=ss.filter(x=>x.active).length;$('com-stock').textContent=ff.reduce((sum,x)=>sum+Number(x.available_units),0);$('com-shift').textContent=shift?'Abierta':'Cerrada';
 $('com-cash-info').textContent=shift?'Esperado: '+money(shift.expected_cash)+' · Ventas digitales: '+money(shift.digital_sales):'Abre un turno para registrar ventas.';
 tables.forEach(id=>$(id).replaceChildren());for(const f of finished.filter(x=>Number(x.available_units)>0))row('finished-rows',[f.label,f.batch_id.slice(0,8),f.available_units,f.price==null?'Sin precio':money(f.price)]);
 if(!finished.some(x=>Number(x.available_units)>0))row('finished-rows',['Sin existencias','—','—','—']);
 for(const p of ph)row('purchase-history',[date(p.created_at),supplierById.get(p.supplier_id)||p.supplier_id,money(p.total),p.id.slice(0,8)]);if(!ph.length)row('purchase-history',['Sin compras','—','—','—']);
 for(const s of sh)row('sale-history',[date(s.created_at),paymentNames[s.payment_method]||s.payment_method,money(s.total),s.id.slice(0,8)]);if(!sh.length)row('sale-history',['Sin ventas','—','—','—']);
 forms.forEach(f=>$(f).reset());options($('price-recipe'),rr.map(r=>[r.id,r.name+' · v'+r.version+(priceById.has(r.id)?' · '+money(priceById.get(r.id)):' · Sin precio')]));options($('purchase-supplier'),ss.filter(x=>x.active).map(x=>[x.id,x.name]));
 $('supplier-form').hidden=!permissions.manager;$('price-form').hidden=!(permissions.active&&permissions.has('prices'))||!rr.length;$('cash-open-form').hidden=!(permissions.active&&permissions.has('cash'))||!!shift;$('cash-close-form').hidden=!manager||!shift;
 $('purchase-form').hidden=!permissions.manager||!ss.some(x=>x.active)||!ii.some(x=>x.active);$('sale-form').hidden=!permissions.movement||!shift||!saleable().length;
 for(const kind of ['purchase','sale']){$(kind+'-lines').replaceChildren();if(kind==='purchase'&&!$(kind+'-form').hidden)addLine(kind);else preview(kind);}
 await catalogOrders.refresh(scope,catalog,permissions);renderPos();loaded=true;$('commerce-content').hidden=false;msg(!permissions.active?'Suscripción inactiva: solo consulta y cierre de caja por administrador.':'');
 }catch(e){loaded=false;msg('No se pudo cargar el módulo comercial. Actualiza para volver a consultar.');if(!api.hasSession())throw e;}}
 async function open(next){scope=next;$('commerce-area').hidden=false;$('commerce-scope').textContent=next.label;await refresh();}
 async function execute(action,success,after){try{await action();}catch(e){msg('Operación no confirmada. Comprueba el historial; conserva los mismos datos si reintentas en esta sesión.');if(!api.hasSession())throw e;return;}await refresh();if(loaded)msg(success);if(after)await after();await onChange();}
 function submit(id,fn){$(id).addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!scope||!loaded)return;try{await fn();}catch(e){if(!api.hasSession())throw e;msg(e.message||'Operación inválida.');}});});}
 $('commerce-reload').addEventListener('click',()=>run(refresh));$('pos-search').addEventListener('input',renderPos);$('purchase-add').addEventListener('click',()=>addLine('purchase'));$('sale-add').addEventListener('click',()=>addLine('sale'));$('purchase-supplier').addEventListener('change',()=>preview('purchase'));$('sale-payment').addEventListener('change',()=>preview('sale'));
 submit('supplier-form',async()=>{if(!permissions.manager)return;const name=$('supplier-name').value.trim();if(!name)throw Error('Escribe el proveedor.');await execute(()=>api.addSupplier(scope.bakery,name),'Proveedor registrado.');});
 submit('price-form',async()=>{if(!permissions.active||!permissions.has('prices'))return;const r=$('price-recipe').value,p=Number(scaled($('price-amount').value,2,999999999999n))/100;if(!r)throw Error('Selecciona receta.');await execute(()=>api.setPrice(scope.bakery,r,p),'Precio guardado.');});
 submit('cash-open-form',async()=>{if(!permissions.active||!permissions.has('cash')||shift)return;const a=Number(scaled($('cash-opening').value,2,99999999999n,true))/100;const payload=['open',scope.bakery,scope.branch,a];await execute(async()=>{await api.openCash(scope.bakery,scope.branch,tracker.id(payload),a);tracker.complete(payload);},'Caja abierta.');});
 submit('cash-close-form',async()=>{if(!permissions.has('cash')||!shift||!$('cash-confirm').checked)return;const a=Number(scaled($('cash-counted').value,2,99999999999n,true))/100;await execute(()=>api.closeCash(scope.bakery,scope.branch,shift.shift_id,a),'Caja cerrada.');});
 submit('purchase-form',async()=>{if(!permissions.manager||!$('purchase-confirm').checked)return;const d=draft('purchase'),s=$('purchase-supplier').value;if(!s)throw Error('Selecciona proveedor.');const payload=['purchase',scope.bakery,scope.branch,s,d.items];await execute(async()=>{await api.receivePurchase(scope.bakery,scope.branch,s,tracker.id(payload),d.items);tracker.complete(payload);},'Compra recibida; insumos actualizados.',onPurchase);});
 submit('sale-form',async()=>{if(!permissions.movement||!shift||!$('sale-confirm').checked)return;const d=draft('sale'),p=$('sale-payment').value,payload=['sale',scope.bakery,scope.branch,p,d.items];await execute(async()=>{await api.recordSale(scope.bakery,scope.branch,tracker.id(payload),p,d.items);tracker.complete(payload);},'Venta registrada; existencias y caja actualizadas.');});
 return {open,clear,refresh};
}
if(typeof module!=='undefined')module.exports={scaled,centsText,purchaseDraft,saleDraft};
