'use strict';
// Mount only the original application markup; production login/config/API scripts are never loaded.
(async function(){
 const $=id=>document.getElementById(id),root=$('demo-root'),notice=$('demo-notice'),selector=$('demo-role');let api=createDemoData(),busy=false,template=null,current='owner';
 const say=t=>{notice.textContent=t;};
 const help='Modo demostración: operaciones simuladas en memoria, sin cuentas, correos, cobros ni conexión a Supabase. Traslados, conciliación, merma por lote y entrega final no se simulan.';
 function lock(value){busy=value;selector.disabled=value;$('demo-reset').disabled=value;}
 async function run(task){if(busy)return;lock(true);try{await task();}catch(e){say('No se completó la simulación: '+(e.message||'operación no disponible'));}finally{lock(false);}}
 function unsupported(){for(const id of ['waste-form','transfer-form','count-form']){const form=$(id);if(!form)continue;form.addEventListener('submit',e=>{e.preventDefault();e.stopImmediatePropagation();say('Esta operación solo se muestra visualmente en la demo.');},true);}}
 async function mount(role){
 current=role;api.setRole(role);root.replaceChildren();
 if(role==='platform'){
 const shell=document.createElement('div');shell.id='platform-workspace';shell.className='admin-layout';shell.append(template.querySelector('#platform-workspace-template').content.cloneNode(true));root.append(shell);const platform=createPlatformController({api,run,isBusy:()=>busy,onLogout:async()=>{selector.value='owner';await mount('owner')}});await platform.open('superadmin@example.test');say(help+' Superadministración ficticia.');return;
 }
 const card=document.createElement('div');card.id='portal-card';card.className='card';const account=template.querySelector('#account').cloneNode(true);account.hidden=false;card.append(account);root.append(card);const nav=createWorkspaceNavigation(),owner=role==='owner',memberRole=owner?'owner':'admin';
 $('account-email').textContent=owner?'dueno@example.test':'trabajador@example.test';
 const inv=createInventoryController({api,run,onChange:()=>Promise.all([prod.refresh(),commerce.refresh()])}),prod=createProductionController({api,run,onChange:()=>Promise.all([inv.refresh(),commerce.refresh()])}),commerce=createCommerceController({api,run,onPurchase:()=>Promise.all([inv.refresh(),prod.refresh()]),onChange:()=>finance.refresh()}),finance=createFinanceController({api,run,onChange:()=>commerce.refresh()}),services=createAccountServices(api,run,async()=>mount(current));
 unsupported();
 const name='Panadería Aurora',bakery='aurora';
 const b=document.createElement('button');b.type='button';b.className='business';b.textContent=name+' · '+(owner?'Administrador':'Empleado');b.setAttribute('aria-pressed','true');b.addEventListener('click',()=>run(load));$('businesses').replaceChildren(b);
 async function branch(){
 const br=$('branch').selectedOptions[0];if(!br)return;
 inv.clear();prod.clear();commerce.clear();finance.clear();const grants=await api.myPermissions(bakery),has=(...keys)=>owner||keys.some(k=>grants.includes(k)),scope={bakery,branch:br.value,role:memberRole,grants,label:name+' · '+br.textContent};$('branch-info').textContent='Sucursal de ejemplo: '+br.textContent+' (datos compartidos en la simulación)';
 if(has('inventory'))await inv.open(scope);if(has('recipes','production'))await prod.open(scope);if(has('purchases','sales','prices','cash'))await commerce.open(scope);if(has('cash','reports'))await finance.open(scope);
 nav.setContext({available:true,business:true,label:scope.label,memberRole,grants,reset:true});
 }
 async function load(){
 const br=await api.branches(bakery);$('branch').replaceChildren();for(const r of br){const o=document.createElement('option');o.value=r.id;o.textContent=r.name;$('branch').append(o);}$('branch-box').hidden=false;$('branch-create-form').hidden=!owner;$('onboard').hidden=true;
 if(owner){const [s]=await api.subscription(bakery),p=(await api.plans()).find(x=>x.code===s.plan_code);$('own-subscription').hidden=false;$('own-plan-status').textContent=p.name+' · '+s.status+' · '+new Date(s.valid_until).toLocaleDateString('es-PE');$('own-plan-limits').textContent=br.length+' / '+p.branch_limit+' sucursales · Hasta '+p.member_limit+' miembros';}
 await services.refreshAccount();await services.scope(bakery,memberRole);await branch();
 }
 $('branch').addEventListener('change',()=>run(branch));$('reload').addEventListener('click',()=>run(load));$('logout').addEventListener('click',()=>{location.href='index.html'});
 $('branch-create-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!owner)return;await api.addBranch(bakery,$('branch-create-name').value.trim());$('branch-create-form').reset();await load();});});
 await load();say(help+(owner?' Cambia los permisos del trabajador en Trabajadores y luego selecciona su rol.':' Solo se muestran los módulos permitidos por el administrador de ejemplo.'));
 }
 try{
 const response=await fetch('access.html',{credentials:'omit',cache:'no-store',redirect:'error'});if(!response.ok)throw Error('No se pudo cargar la interfaz');template=new DOMParser().parseFromString(await response.text(),'text/html');if(!template.querySelector('#account')||!template.querySelector('#platform-workspace-template'))throw Error('Plantillas no disponibles');
 const requested=new URLSearchParams(location.search).get('rol');selector.value=['platform','owner','employee'].includes(requested)?requested:'owner';selector.addEventListener('change',()=>run(()=>mount(selector.value)));$('demo-reset').addEventListener('click',()=>run(async()=>{api=createDemoData();await mount(selector.value)}));await run(()=>mount(selector.value));
 }catch(e){say('No se pudo abrir la demo. Recarga la página publicada o sirve el repositorio por HTTP local.');}
})();
