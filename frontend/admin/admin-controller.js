'use strict';
const subscriptionLabels={trial:'En prueba',active:'Activo',expired:'Vencido',suspended:'Suspendido',cancelled:'Cancelado'};
function effectiveStatus(row,now=Date.now()){
 if(!['trial','active','suspended','cancelled'].includes(row.status)||!Number.isFinite(Date.parse(row.valid_until)))throw Error('Estado inválido');
 return ['trial','active'].includes(row.status)&&Date.parse(row.valid_until)<=now?'expired':row.status;
}
function customerSummary(rows,now=Date.now()){
 const result={total:rows.length,active:0,trial:0,expired:0,suspended:0,cancelled:0};for(const row of rows)result[effectiveStatus(row,now)]++;return result;
}
function filterCustomers(rows,query,state,plan,now=Date.now()){
 const q=String(query).trim().toLocaleLowerCase('es');
 return rows.filter(r=>r.name.toLocaleLowerCase('es').includes(q)&&(!state||effectiveStatus(r,now)===state)&&(!plan||r.plan_code===plan));
}
function subscriptionDraft(row,plan,status,date,plans,now=Date.now()){
 if(!row||!plans.some(p=>p.code===plan)||!['trial','active','suspended','cancelled'].includes(status))throw Error('Plan o estado inválidos.');
 let until=row.valid_until;
 if(date){if(!/^\d{4}-\d{2}-\d{2}$/.test(date))throw Error('Fecha inválida.');
 const check=new Date(date+'T00:00:00Z');if(!Number.isFinite(check.getTime())||check.toISOString().slice(0,10)!==date)throw Error('Fecha inválida.');
 // End of the chosen Lima calendar day is represented as exclusive midnight next day.
 const next=new Date(check.getTime()+86400000).toISOString().slice(0,10);
 until=new Date(next+'T00:00:00-05:00').toISOString();}
 if(!Number.isFinite(Date.parse(until))||(['trial','active'].includes(status)&&Date.parse(until)<=now))throw Error('Una suscripción activa o en prueba necesita vigencia futura.');
 return {plan,status,until};
}
function adminInit(){
 const $=id=>document.getElementById(id),cfg=validateConfig(window.BAKERY_CONFIG);
 if(location.hash)history.replaceState(null,'',location.pathname+location.search);
 if(!cfg){$('admin-login-message').textContent='Conexión pendiente. Configura una instancia dedicada antes de utilizar este portal.';return;}
 const api=createApi(cfg);let rows=[],plans=[],selected=null,busy=false,authorized=false;
 const flow=createAuthFlow({api,run,root:$('admin-auth-flow'),loginForm:$('admin-login'),notify:t=>{$('admin-login-message').textContent=t;},admin:true});
 const billing=createBillingAdmin(api,run,()=>refresh());
 const msg=t=>{$('admin-message').textContent=t;};
 const fmt=v=>new Date(v).toLocaleString('es-PE',{timeZone:'America/Lima'});
 function clearEditor(){selected=null;$('admin-editor').hidden=true;$('admin-edit-form').reset();$('admin-edit-title').textContent='';$('admin-edit-current').textContent='';$('admin-edit-warning').textContent='';}
 function clear(){flow.clear();billing.clear();authorized=false;rows=[];plans=[];clearEditor();$('admin-data').hidden=true;$('admin-panel').hidden=true;$('admin-access').hidden=false;$('admin-user').textContent='';for(const id of ['admin-rows','admin-plans','admin-plan-filter','admin-edit-plan'])$(id).replaceChildren();for(const id of ['adm-total','adm-active','adm-trial','adm-expired','adm-inactive'])$(id).textContent='0';$('admin-search').value='';$('admin-state').value='';$('admin-count').textContent='';msg('');}
 async function run(task){if(busy)return;busy=true;document.querySelectorAll('button,input,select').forEach(e=>e.disabled=true);try{if(!$('admin-panel').hidden&&api.hasSession()&&!(await api.sessionStatus())){try{await api.logout();}catch{}clear();$('admin-login-message').textContent='Sesión sustituida o revocada.';return;}await task();}catch(e){if(!api.hasSession()){clear();$('admin-login-message').textContent='Sesión no disponible. Vuelve a ingresar.';}else msg('No se pudo completar la operación. Actualiza y comprueba tus permisos.');}finally{busy=false;document.querySelectorAll('button,input,select').forEach(e=>e.disabled=false);}}
 function options(el,items){el.replaceChildren();for(const [value,text] of items){const o=document.createElement('option');o.value=value;o.textContent=text;el.append(o);}}
 function table(){if(!authorized)return;const filtered=filterCustomers(rows,$('admin-search').value,$('admin-state').value,$('admin-plan-filter').value),byCode=new Map(plans.map(p=>[p.code,p]));$('admin-rows').replaceChildren();
 for(const r of filtered){const p=byCode.get(r.plan_code),status=effectiveStatus(r),tr=document.createElement('tr');for(const [i,value] of [r.name,p?.name||r.plan_code,subscriptionLabels[status],fmt(r.valid_until),r.active_branches+' / '+(p?.branch_limit??'—'),r.members+' / '+(p?.member_limit??'—')].entries()){const td=document.createElement('td');td.textContent=value;if(i===2)td.dataset.state=status;tr.append(td);}const td=document.createElement('td'),b=document.createElement('button');b.type='button';b.textContent='Gestionar';b.setAttribute('aria-label','Gestionar '+r.name);b.addEventListener('click',()=>{if(!busy)edit(r.bakery_id);});td.append(b);tr.append(td);$('admin-rows').append(tr);}
 if(!filtered.length){const tr=document.createElement('tr'),td=document.createElement('td');td.colSpan=7;td.textContent='No hay clientes para este filtro.';tr.append(td);$('admin-rows').append(tr);}$('admin-count').textContent=filtered.length+' de '+rows.length+' clientes';}
 function warning(){const r=rows.find(x=>x.bakery_id===selected),p=plans.find(x=>x.code===$('admin-edit-plan').value);if(!r||!p)return;const parts=[];if(Number(r.active_branches)>p.branch_limit||Number(r.members)>p.member_limit)parts.push('El uso actual supera el nuevo límite. No se eliminarán registros.');if(['suspended','cancelled'].includes($('admin-edit-status').value))parts.push('Se bloquearán nuevas operaciones, conservando consulta y cierre de caja.');$('admin-edit-warning').textContent=parts.join(' ');$('admin-confirm').checked=false;}
 function edit(id){clearEditor();const r=rows.find(x=>x.bakery_id===id);if(!authorized||!r)return;selected=id;$('admin-edit-title').textContent='Gestionar '+r.name;$('admin-edit-current').textContent='Estado actual: '+subscriptionLabels[effectiveStatus(r)]+' · Vigencia: '+fmt(r.valid_until);options($('admin-edit-plan'),plans.map(p=>[p.code,p.name]));$('admin-edit-plan').value=r.plan_code;$('admin-edit-status').value=r.status;$('admin-editor').hidden=false;warning();$('admin-edit-plan').focus();}
 async function refresh(){clearEditor();authorized=false;$('admin-data').hidden=true;rows=[];plans=[];$('admin-rows').replaceChildren();const [customers,available]=await Promise.all([collectPages(c=>api.customers(c),'bakery_id'),api.plans()]);if(!Array.isArray(available)||!available.length)throw Error('Planes no disponibles');plans=available;rows=customers;const t=customerSummary(rows);for(const [id,v] of Object.entries({'adm-total':t.total,'adm-active':t.active,'adm-trial':t.trial,'adm-expired':t.expired,'adm-inactive':t.suspended+t.cancelled}))$(id).textContent=v;
 $('admin-plans').replaceChildren();for(const p of plans){const box=document.createElement('div'),title=document.createElement('strong'),desc=document.createElement('p');title.textContent=p.name;desc.textContent=p.branch_limit+' sucursales · '+p.member_limit+' miembros';box.append(title,desc);$('admin-plans').append(box);}
 const prior=$('admin-plan-filter').value;options($('admin-plan-filter'),[['','Todos'],...plans.map(p=>[p.code,p.name])]);if(plans.some(p=>p.code===prior))$('admin-plan-filter').value=prior;
 authorized=true;table();await billing.refresh();$('admin-data').hidden=false;msg('');}
 $('admin-login').hidden=false;
 $('admin-forgot').addEventListener('click',()=>run(async()=>{if(api.hasSession())await api.logout();flow.reset();}));
 $('admin-login').addEventListener('submit',e=>{e.preventDefault();const email=$('admin-email').value.trim(),pw=$('admin-password').value;$('admin-password').value='';run(async()=>{try{const user=await api.login(email,pw);const label=$('admin-device').value.trim()||'Administración';await flow.mfa(async()=>{await api.registerSession(label);await refresh();$('admin-user').textContent=user?.email||email;$('admin-access').hidden=true;$('admin-panel').hidden=false;$('admin-login-message').textContent='';});}catch{try{await api.logout();}catch{}clear();$('admin-login-message').textContent='No se pudo acceder. Comprueba las credenciales, autorización de plataforma y conexión.';}});});
 setInterval(()=>{if(!busy&&!$('admin-panel').hidden&&api.hasSession())run(async()=>{});},60000);
 $('admin-reload').addEventListener('click',()=>run(refresh));$('admin-logout').addEventListener('click',()=>run(async()=>{try{await api.logout();}finally{clear();$('admin-login-message').textContent='Acceso local cerrado.';}}));
 for(const id of ['admin-search','admin-state','admin-plan-filter'])$(id).addEventListener(id==='admin-search'?'input':'change',table);
 for(const id of ['admin-edit-plan','admin-edit-status','admin-edit-date'])$(id).addEventListener('change',warning);
 $('admin-cancel').addEventListener('click',clearEditor);
 $('admin-edit-form').addEventListener('submit',e=>{e.preventDefault();run(async()=>{if(!authorized||!selected||!$('admin-confirm').checked)return;const r=rows.find(x=>x.bakery_id===selected);let d;try{d=subscriptionDraft(r,$('admin-edit-plan').value,$('admin-edit-status').value,$('admin-edit-date').value,plans);}catch(e){msg(e.message);return;}
 try{await api.changeSubscription(r.bakery_id,d.plan,d.status,d.until);}catch(e){msg('Cambio no confirmado. Actualiza y comprueba el estado antes de repetir.');if(!api.hasSession())throw e;return;}
 await refresh();msg('Suscripción actualizada.');});});
}
if(typeof document!=='undefined')adminInit();
if(typeof module!=='undefined')module.exports={effectiveStatus,customerSummary,filterCustomers,subscriptionDraft};
