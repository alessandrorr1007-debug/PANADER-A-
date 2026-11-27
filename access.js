'use strict';
function validateConfig(c){
 if(!c || typeof c.url!=='string'||typeof c.publishableKey!=='string')return null;
 try{const u=new URL(c.url);if(u.protocol!=='https:'||!(/^[a-z0-9-]+\.supabase\.co$/.test(u.hostname))||u.username||u.password||u.port||u.pathname!=='/'||u.search||u.hash||!/^sb_publishable_[A-Za-z0-9_-]+$/.test(c.publishableKey))return null;return {url:u.origin,key:c.publishableKey};}catch{return null;}
}
function createApi(config,fetcher=fetch){
 let token=null;
 async function request(path,method='GET',body,auth=false,minimal=false){
  if(auth&&!token)throw new Error('Sesión no disponible');
  const headers={apikey:config.key,'Content-Type':'application/json'};if(auth)headers.Authorization='Bearer '+token;if(minimal)headers.Prefer='return=minimal';
  const response=await fetcher(config.url+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',redirect:'error',credentials:'omit'});
  if(!response.ok){if(auth&&response.status===401)token=null;throw new Error('HTTP '+response.status);}
  return response.status===204||(minimal&&response.status===201)?null:response.json();
 }
 return {signup:(email,password)=>request('/auth/v1/signup','POST',{email,password}),
 async login(email,password){token=null;const data=await request('/auth/v1/token?grant_type=password','POST',{email,password});if(!data?.access_token)throw new Error('Sesión no disponible');token=data.access_token;return data.user;},
 async logout(){try{if(token)await request('/auth/v1/logout?scope=local','POST',undefined,true);}finally{token=null;}},
 hasSession:()=>!!token,
 businesses:()=>request('/rest/v1/bakery_members?select=bakery_id,role,bakeries(id,name)&order=bakery_id','GET',undefined,true),
 branches:id=>request('/rest/v1/branches?select=id,name,active&bakery_id=eq.'+encodeURIComponent(id)+'&order=name','GET',undefined,true),
 create:(name,branch)=>request('/rest/v1/rpc/create_initial_bakery','POST',{p_name:name,p_branch:branch},true),
 ingredients:(id,cursor='')=>request('/rest/v1/ingredients?select=id,name,unit,reference_cost,active&bakery_id=eq.'+encodeURIComponent(id)+'&order=id.asc&limit=200'+(cursor?'&id=gt.'+encodeURIComponent(cursor):''),'GET',undefined,true),
 balances:(id,branch,cursor='')=>request('/rest/v1/stock_balances?select=ingredient_id,quantity,minimum&bakery_id=eq.'+encodeURIComponent(id)+'&branch_id=eq.'+encodeURIComponent(branch)+'&order=ingredient_id.asc&limit=200'+(cursor?'&ingredient_id=gt.'+encodeURIComponent(cursor):''),'GET',undefined,true),
 movements:(id,branch)=>request('/rest/v1/stock_movements?select=id,ingredient_id,direction,quantity,reason,created_at&bakery_id=eq.'+encodeURIComponent(id)+'&branch_id=eq.'+encodeURIComponent(branch)+'&order=created_at.desc,id.desc&limit=30','GET',undefined,true),
 subscription:id=>request('/rest/v1/saas_subscriptions?select=status,valid_until&bakery_id=eq.'+encodeURIComponent(id),'GET',undefined,true),
 addIngredient:(id,name,unit,cost)=>request('/rest/v1/ingredients','POST',{bakery_id:id,name,unit,reference_cost:cost},true,true),
 movement:(id,branch,ingredient,req,direction,quantity,reason)=>request('/rest/v1/rpc/record_stock_movement','POST',{p_bakery:id,p_branch:branch,p_ingredient:ingredient,p_request:req,p_direction:direction,p_quantity:quantity,p_reason:reason},true),
 minimum:(id,branch,ingredient,quantity)=>request('/rest/v1/rpc/set_stock_minimum','POST',{p_bakery:id,p_branch:branch,p_ingredient:ingredient,p_minimum:quantity},true)};
}
function init(){
 const $=id=>document.getElementById(id),cfg=validateConfig(window.BAKERY_CONFIG);
 // Confirmation links may return an implicit-flow fragment; do not persist or consume it.
 if(location.hash)history.replaceState(null,'',location.pathname+location.search);
 if(!cfg){$('setup').hidden=false;return;}
 const api=createApi(cfg);let mode='login',busy=false,selected='',businesses=[],branchList=[];
 const say=text=>{$('status').textContent=text;};
 const inventory=createInventoryController({api,run:task=>run(task)});
 function clearAccount(){inventory.clear(true);$('account').hidden=true;$('auth').hidden=false;$('account-email').textContent='';$('businesses').replaceChildren();$('branch').replaceChildren();$('branch-info').textContent='';$('branch-box').hidden=true;$('onboard').hidden=true;$('onboard').reset();selected='';businesses=[];branchList=[];}
 function setMode(next){mode=next;$('login-tab').setAttribute('aria-pressed',String(next==='login'));$('signup-tab').setAttribute('aria-pressed',String(next==='signup'));$('auth-title').textContent=next==='login'?'Inicia sesión':'Crea tu cuenta';$('auth-submit').textContent=next==='login'?'Iniciar sesión':'Registrarme';$('password').autocomplete=next==='login'?'current-password':'new-password';$('password').minLength=next==='signup'?8:1;$('password').value='';}
 async function run(task){if(busy)return;busy=true;document.querySelectorAll('button,input,select').forEach(e=>e.disabled=true);say('');try{await task();}catch{if(!api.hasSession()&&!$('account').hidden)clearAccount();say('No se pudo completar la operación. Verifica tus datos o vuelve a iniciar sesión.');}finally{busy=false;document.querySelectorAll('button,input,select').forEach(e=>e.disabled=false);}}
 async function pick(id){inventory.clear();selected='';branchList=[];$('branch-box').hidden=true;$('branch').replaceChildren();$('branch-info').textContent='';$('businesses').querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed','false'));const rows=await api.branches(id);selected=id;branchList=rows.filter(b=>b.active);$('businesses').querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.id===id)));for(const b of branchList){const option=document.createElement('option');option.value=b.id;option.textContent=b.name;$('branch').append(option);}$('branch-box').hidden=false;await showBranch();}
 async function showBranch(){inventory.clear();const b=branchList.find(b=>b.id===$('branch').value);$('branch-info').textContent=b?'Sucursal seleccionada: '+b.name:'No hay sucursales activas.';const m=businesses.find(x=>x.bakery_id===selected);if(b&&m)await inventory.open({bakery:selected,branch:b.id,role:m.role,label:(m.bakeries?.name||'Negocio')+' · '+b.name});}
 async function load(){ inventory.clear();$('businesses').replaceChildren();$('branch-box').hidden=true;$('onboard').hidden=true;selected='';branchList=[];businesses=await api.businesses();$('onboard').hidden=businesses.length!==0;for(const m of businesses){const b=document.createElement('button');b.type='button';b.className='business';b.dataset.id=m.bakery_id;b.setAttribute('aria-pressed','false');b.textContent=(m.bakeries?.name||'Negocio')+' · '+({owner:'Propietario',admin:'Administrador',operator:'Operario',viewer:'Consulta'}[m.role]||'Miembro');b.addEventListener('click',()=>run(()=>pick(m.bakery_id)));$('businesses').append(b);}if(businesses.length)await pick(businesses[0].bakery_id);}
 $('auth').hidden=false;setMode('login');
 $('login-tab').addEventListener('click',()=>setMode('login'));$('signup-tab').addEventListener('click',()=>setMode('signup'));
 $('auth-form').addEventListener('submit',e=>{e.preventDefault();const email=$('email').value.trim(),password=$('password').value;$('password').value='';run(async()=>{if(mode==='signup'){await api.signup(email,password);setMode('login');say('Si el registro está disponible, recibirás un correo de confirmación. Confirma tu correo e inicia sesión.');}else{const user=await api.login(email,password);$('account-email').textContent=user?.email||email;$('auth').hidden=true;$('account').hidden=false;await load();}});});
 $('onboard').addEventListener('submit',e=>{e.preventDefault();const name=$('bakery-name').value.trim(),branch=$('branch-name').value.trim();run(async()=>{if(!name||!branch){say('Escribe el nombre del negocio y la sucursal.');return;}await api.create(name,branch);$('onboard').reset();await load();say('Espacio de trabajo creado.');});});
 $('branch').addEventListener('change',()=>run(showBranch));$('reload').addEventListener('click',()=>run(load));
 $('logout').addEventListener('click',()=>run(async()=>{try{await api.logout();say('Sesión cerrada.');}catch{say('Se cerró el acceso local; no se confirmó la revocación remota.');}finally{clearAccount();setMode('login');}}));
}
if(typeof document!=='undefined')init();
if(typeof module!=='undefined')module.exports={validateConfig,createApi};
