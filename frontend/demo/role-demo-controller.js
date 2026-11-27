'use strict';
// Mount only the original application markup; production login/config/API scripts are never loaded.
(async function(){
 const $=id=>document.getElementById(id),root=$('demo-root'),notice=$('demo-notice'),selector=$('demo-role');let api=createDemoData(),busy=false,template=null,current='owner',afterTask=null;
 const say=t=>{notice.textContent=t;};
 const help='Demostración · Datos ficticios, sin conexión a Supabase. Algunas operaciones avanzadas son solo visuales.';
 function lock(value){busy=value;selector.disabled=value;$('demo-reset').disabled=value;}
 async function run(task){if(busy)return;lock(true);try{await task();if(afterTask)await afterTask();}catch(e){say('No se completó la simulación: '+(e.message||'operación no disponible'));}finally{lock(false);}}
 function unsupported(){for(const id of ['waste-form','transfer-form','count-form']){const form=$(id);if(!form)continue;form.addEventListener('submit',e=>{e.preventDefault();e.stopImmediatePropagation();say('Esta operación solo se muestra visualmente en la demo.');},true);}}
 async function mount(role){
 current=role;afterTask=null;api.setRole(role);root.replaceChildren();
 if(role==='platform'){
 const shell=document.createElement('div');shell.id='platform-workspace';shell.className='admin-layout';shell.append(template.querySelector('#platform-workspace-template').content.cloneNode(true));root.append(shell);const platform=createPlatformController({api,run,isBusy:()=>busy,onLogout:async()=>{selector.value='owner';await mount('owner')}});await platform.open('superadmin@example.test');say(help+' Superadministración ficticia.');return;
 }
 const card=document.createElement('div');card.id='portal-card';card.className='demo-workspace-frame';const account=template.querySelector('#account').cloneNode(true);account.hidden=false;card.append(account);root.append(card);const owner=role==='owner',memberRole=owner?'owner':'admin';
 if(owner){const summary=document.createElement('section');summary.id='demo-admin-summary';summary.className='demo-admin-summary';summary.setAttribute('aria-label','Actividad simulada del negocio');account.querySelector('.overview-kpis').after(summary);}
 const nav=createWorkspaceNavigation();
 $('account-email').textContent=owner?'dueno@example.test':'trabajador@example.test';
 const inv=createInventoryController({api,run,onChange:()=>Promise.all([prod.refresh(),commerce.refresh()])}),prod=createProductionController({api,run,onChange:()=>Promise.all([inv.refresh(),commerce.refresh()])}),commerce=createCommerceController({api,run,onPurchase:()=>Promise.all([inv.refresh(),prod.refresh()]),onChange:()=>finance.refresh()}),finance=createFinanceController({api,run,onChange:()=>commerce.refresh()}),services=createAccountServices(api,run,async()=>mount(current));
 unsupported();
 const name='Panadería Aurora',bakery='aurora';
 const money=n=>'S/ '+Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:2});
 function node(tag,cls,txt){const el=document.createElement(tag);if(cls)el.className=cls;if(txt!==undefined)el.textContent=txt;return el;}
 async function dashboard(){
 nav.sync();if(!owner)return;const container=$('demo-admin-summary');if(!container)return;
 const days=reportDays(7),[series,stock,balances,sub,team,finished]=await Promise.all([api.dailySales(bakery,'principal',days[0],days.at(-1),''),api.ingredients(bakery,''),api.balances(bakery,'principal',''),api.subscription(bakery),api.teamMembers(bakery),api.finished(bakery,'principal','')]);
 const byDay=new Map(series.map(r=>[r.business_date,r])),values=days.map(d=>Number(byDay.get(d)?.revenue||0)),total=values.reduce((n,v)=>n+v,0),max=Math.max(1,...values);
 const chart=node('article','demo-summary-card'),head=node('div','demo-summary-head'),title=node('div');title.append(node('h3','','Ventas de los últimos 7 días'),node('small','','Historial de ejemplo · PEN'));head.append(title,node('span','demo-summary-tag','Simulado'));chart.append(head,node('strong','demo-chart-total',money(total)));
 const bars=node('div','demo-sales-bars');bars.setAttribute('role','img');bars.setAttribute('aria-label','Ventas diarias simuladas: '+values.map(money).join(', '));
 days.forEach((d,i)=>{const col=node('div','demo-sales-col'),track=node('div','demo-sales-track'),bar=node('div','demo-sales-bar');bar.style.height=Math.max(2,values[i]/max*100)+'%';track.append(bar);col.append(node('small','demo-bar-value',String(values[i].toFixed(0))),track,node('small','',d.slice(8)+'/'+d.slice(5,7)));bars.append(col);});chart.append(bars);
 const status=node('article','demo-summary-card'),statusHead=node('div','demo-summary-head'),statusTitle=node('div');statusTitle.append(node('h3','','Estado del negocio'),node('small','','Información de esta demostración'));statusHead.append(statusTitle);status.append(statusHead);
 const low=balances.filter(b=>Number(b.quantity)<Number(b.minimum));const rows=[['Inventario',low.length+' insumo(s) bajo el mínimo'],['Productos disponibles',String(finished.reduce((n,x)=>n+Number(x.available_units),0))+' unidades'],['Equipo',team.length+' miembros'],['Suscripción',({active:'Activa',trial:'En prueba',suspended:'Suspendida',cancelled:'Cancelada'})[sub[0]?.status]||'No disponible']];
 for(const [label,value] of rows){const r=node('div','demo-status-row');r.append(node('span','',label),node('strong','',value));status.append(r);}
 const inventory=node('div','demo-stock-list');for(const item of stock.filter(x=>low.some(b=>b.ingredient_id===x.id))){const b=low.find(x=>x.ingredient_id===item.id);inventory.append(node('p','',item.name+' · '+b.quantity+' '+item.unit+' disponibles'));}if(inventory.children.length)status.append(inventory);
 container.replaceChildren(chart,status);
 }
 afterTask=dashboard;
 const b=document.createElement('button');b.type='button';b.className='business';b.textContent=name+' · '+(owner?'Administrador':'Empleado');b.setAttribute('aria-pressed','true');b.addEventListener('click',()=>run(load));$('businesses').replaceChildren(b);
 async function branch(){
 const br=$('branch').selectedOptions[0];if(!br)return;
 inv.clear();prod.clear();commerce.clear();finance.clear();const grants=await api.myPermissions(bakery),has=(...keys)=>owner||keys.some(k=>grants.includes(k)),scope={bakery,branch:br.value,role:memberRole,grants,label:name+' · '+br.textContent};$('branch-info').textContent='Sucursal de ejemplo: '+br.textContent+' (datos compartidos en la simulación)';
 if(has('inventory'))await inv.open(scope);if(has('recipes','production'))await prod.open(scope);if(has('purchases','sales','prices','cash'))await commerce.open(scope);if(has('cash','reports'))await finance.open(scope);
 nav.setContext({available:true,business:true,label:scope.label,memberRole,grants,reset:true});
 await dashboard();
 }
 async function load(){
 const br=await api.branches(bakery);$('branch').replaceChildren();for(const r of br){const o=document.createElement('option');o.value=r.id;o.textContent=r.name;$('branch').append(o);}$('branch-box').hidden=false;$('branch-create-form').hidden=!owner;$('onboard').hidden=true;
 if(owner){const [s]=await api.subscription(bakery),p=(await api.plans()).find(x=>x.code===s.plan_code);$('own-subscription').hidden=false;$('own-plan-status').textContent=p.name+' · '+s.status+' · '+new Date(s.valid_until).toLocaleDateString('es-PE');$('own-plan-limits').textContent=br.length+' / '+p.branch_limit+' sucursales · Hasta '+p.member_limit+' miembros';}
 await services.refreshAccount();await services.scope(bakery,memberRole);await branch();
 }
 $('branch').addEventListener('change',()=>run(branch));$('reload').addEventListener('click',()=>run(load));$('logout').addEventListener('click',()=>{location.href='index.html'});
 $('branch-create-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!owner)return;await api.addBranch(bakery,$('branch-create-name').value.trim());$('branch-create-form').reset();await load();});});
 await load();say(help+(owner?' Prueba los módulos desde el menú lateral.':' Accesos según los permisos del trabajador.'));
 }
 try{
 if(typeof workspacePermissions!=='function'||workspacePermissions('owner',[],true,true).length!==13)throw Error('Versión de navegación incompatible');
 const response=await fetch('access.html?v=20261127-4',{credentials:'omit',cache:'no-store',redirect:'error'});if(!response.ok)throw Error('No se pudo cargar la interfaz');template=new DOMParser().parseFromString(await response.text(),'text/html');if(!template.querySelector('#account #workspace-menu-toggle')||!template.querySelector('#account [data-nav="team"]')||!template.querySelector('#platform-workspace-template'))throw Error('Plantillas no disponibles');
 const requested=new URLSearchParams(location.search).get('rol');selector.value=['platform','owner','employee'].includes(requested)?requested:'owner';selector.addEventListener('change',()=>run(()=>mount(selector.value)));$('demo-reset').addEventListener('click',()=>run(async()=>{api=createDemoData();await mount(selector.value)}));await run(()=>mount(selector.value));
 }catch(e){say('No se pudo abrir la demo. Recarga la página publicada o sirve el repositorio por HTTP local.');}
})();
