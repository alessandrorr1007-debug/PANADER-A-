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
 const list=(table,query)=>request('/rest/v1/'+table+'?'+query,'GET',undefined,true);
 const scoped=(id,branch)=>'&bakery_id=eq.'+encodeURIComponent(id)+(branch?'&branch_id=eq.'+encodeURIComponent(branch):'');
 const page=(key,cursor)=>'&order='+key+'.asc&limit=200'+(cursor?'&'+key+'=gt.'+encodeURIComponent(cursor):'');
 const rpc=(name,body)=>request('/rest/v1/rpc/'+name,'POST',body,true);
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
 subscription:id=>request('/rest/v1/saas_subscriptions?select=plan_code,status,valid_until&bakery_id=eq.'+encodeURIComponent(id),'GET',undefined,true),
 addIngredient:(id,name,unit,cost)=>request('/rest/v1/ingredients','POST',{bakery_id:id,name,unit,reference_cost:cost},true,true),
 movement:(id,branch,ingredient,req,direction,quantity,reason)=>request('/rest/v1/rpc/record_stock_movement','POST',{p_bakery:id,p_branch:branch,p_ingredient:ingredient,p_request:req,p_direction:direction,p_quantity:quantity,p_reason:reason},true),
 minimum:(id,branch,ingredient,quantity)=>request('/rest/v1/rpc/set_stock_minimum','POST',{p_bakery:id,p_branch:branch,p_ingredient:ingredient,p_minimum:quantity},true),
 recipes:(id,cursor='')=>request('/rest/v1/recipe_versions?select=id,name,version,yield_units&bakery_id=eq.'+encodeURIComponent(id)+'&order=id.asc&limit=200'+(cursor?'&id=gt.'+encodeURIComponent(cursor):''),'GET',undefined,true),
 recipeItems:(id,recipe,cursor='')=>request('/rest/v1/recipe_items?select=ingredient_id,quantity&bakery_id=eq.'+encodeURIComponent(id)+'&recipe_id=eq.'+encodeURIComponent(recipe)+'&order=ingredient_id.asc&limit=200'+(cursor?'&ingredient_id=gt.'+encodeURIComponent(cursor):''),'GET',undefined,true),
 batches:(id,branch)=>request('/rest/v1/production_batches?select=id,recipe_id,output_units,reference_cost,created_at&bakery_id=eq.'+encodeURIComponent(id)+'&branch_id=eq.'+encodeURIComponent(branch)+'&order=created_at.desc,id.desc&limit=30','GET',undefined,true),
 createRecipe:(id,name,yieldUnits,items)=>request('/rest/v1/rpc/create_recipe_version','POST',{p_bakery:id,p_name:name,p_yield:yieldUnits,p_items:items},true),
 completeBatch:(id,branch,recipe,req,units)=>request('/rest/v1/rpc/complete_production','POST',{p_bakery:id,p_branch:branch,p_recipe:recipe,p_request:req,p_units:units},true),
 suppliers:(id,cursor='')=>list('suppliers','select=id,name,active'+scoped(id)+page('id',cursor)),
 prices:(id,cursor='')=>list('recipe_prices','select=recipe_id,unit_price'+scoped(id)+page('recipe_id',cursor)),
 finished:(id,branch,cursor='')=>list('finished_stock','select=batch_id,recipe_id,available_units'+scoped(id,branch)+page('batch_id',cursor)),
 cashOpen:(id,branch)=>list('cash_summary','select=shift_id,expected_cash,opening_amount,cash_sales,digital_sales,opened_at'+scoped(id,branch)+'&closed_at=is.null&limit=2'),
 purchases:(id,branch)=>list('purchase_receipts','select=id,supplier_id,total,created_at'+scoped(id,branch)+'&order=created_at.desc,id.desc&limit=30'),
 sales:(id,branch)=>list('sales','select=id,payment_method,total,created_at'+scoped(id,branch)+'&order=created_at.desc,id.desc&limit=30'),
 addSupplier:(id,name)=>request('/rest/v1/suppliers','POST',{bakery_id:id,name},true,true),
 setPrice:(id,recipe,price)=>rpc('set_recipe_price',{p_bakery:id,p_recipe:recipe,p_price:price}),
 openCash:(id,branch,req,amount)=>rpc('open_cash_shift',{p_bakery:id,p_branch:branch,p_request:req,p_opening:amount}),
 closeCash:(id,branch,shift,amount)=>rpc('close_cash_shift',{p_bakery:id,p_branch:branch,p_shift:shift,p_counted:amount}),
 receivePurchase:(id,branch,supplier,req,items)=>rpc('receive_purchase',{p_bakery:id,p_branch:branch,p_supplier:supplier,p_request:req,p_items:items}),
 recordSale:(id,branch,req,payment,items)=>rpc('record_sale',{p_bakery:id,p_branch:branch,p_request:req,p_payment:payment,p_items:items}),
 cashShifts:(id,branch)=>list('cash_summary','select=shift_id,opened_at,closed_at,opening_amount,cash_sales,digital_sales,cash_in,cash_out,expected_cash,counted_cash,difference'+scoped(id,branch)+'&order=opened_at.desc,shift_id.desc&limit=30'),
 cashEntries:(id,shift)=>list('cash_entries','select=id,direction,amount,reason,created_at'+scoped(id)+'&shift_id=eq.'+encodeURIComponent(shift)+'&order=created_at.desc,id.desc&limit=30'),
 addCashEntry:(id,branch,shift,req,direction,amount,reason)=>rpc('add_cash_entry',{p_bakery:id,p_branch:branch,p_shift:shift,p_request:req,p_direction:direction,p_amount:amount,p_reason:reason}),
 dailySales:(id,branch,from,to,cursor='')=>list('daily_sales_summary','select=business_date,sale_count,revenue,units_sold,estimated_ingredient_cost,estimated_ingredient_margin'+scoped(id,branch)+'&business_date=gte.'+encodeURIComponent(from)+'&business_date=lte.'+encodeURIComponent(to)+page('business_date',cursor)),
 dailyPurchases:(id,branch,from,to,cursor='')=>list('daily_purchase_summary','select=business_date,receipt_count,received_cost'+scoped(id,branch)+'&business_date=gte.'+encodeURIComponent(from)+'&business_date=lte.'+encodeURIComponent(to)+page('business_date',cursor)),
 plans:()=>list('saas_plans','select=code,name,branch_limit,member_limit&order=code.asc'),
 customers:(cursor='')=>request('/rest/v1/rpc/list_customers?order=bakery_id.asc&limit=200'+(cursor?'&bakery_id=gt.'+encodeURIComponent(cursor):''),'POST',{},true),
 changeSubscription:(id,plan,status,until)=>rpc('set_subscription',{p_bakery:id,p_plan:plan,p_status:status,p_valid_until:until})};
}
function init(){
 const $=id=>document.getElementById(id),cfg=validateConfig(window.BAKERY_CONFIG);
 // Confirmation links may return an implicit-flow fragment; do not persist or consume it.
 if(location.hash)history.replaceState(null,'',location.pathname+location.search);
 if(!cfg){$('setup').hidden=false;return;}
 const api=createApi(cfg);let mode='login',busy=false,selected='',businesses=[],branchList=[];
 const say=text=>{$('status').textContent=text;};
 const inventory=createInventoryController({api,run:task=>run(task),onChange:()=>Promise.all([production.refresh(),commerce.refresh()])});
 const production=createProductionController({api,run:task=>run(task),onChange:()=>Promise.all([inventory.refresh(),commerce.refresh()])});
 const commerce=createCommerceController({api,run:task=>run(task),onPurchase:()=>Promise.all([inventory.refresh(),production.refresh()]),onChange:()=>finance.refresh()});
 const finance=createFinanceController({api,run:task=>run(task),onChange:()=>commerce.refresh()});
 function clearSubscription(){$('own-subscription').hidden=true;$('own-plan-status').textContent='';$('own-plan-limits').textContent='';}
 async function showSubscription(id,branches){clearSubscription();$('own-subscription').hidden=false;try{const [subs,plans]=await Promise.all([api.subscription(id),api.plans()]);if(!Array.isArray(subs)||subs.length!==1||!Array.isArray(plans))throw Error();const s=subs[0],p=plans.find(x=>x.code===s.plan_code);if(!p)throw Error();const expired=['trial','active'].includes(s.status)&&Date.parse(s.valid_until)<=Date.now();const statuses={trial:'En prueba',active:'Activo',suspended:'Suspendido',cancelled:'Cancelado'};$('own-plan-status').textContent=p.name+' · '+(expired?'Vencido':statuses[s.status]||'No disponible')+' · Vigencia: '+new Date(s.valid_until).toLocaleString('es-PE',{timeZone:'America/Lima'});$('own-plan-limits').textContent='Sucursales activas: '+branches.filter(b=>b.active).length+' / '+p.branch_limit+' · Hasta '+p.member_limit+' miembros';}catch(e){$('own-plan-status').textContent='No se pudo consultar la suscripción.';if(!api.hasSession())throw e;}}
 function clearAccount(){clearSubscription();inventory.clear(true);production.clear(true);commerce.clear(true);finance.clear(true);$('account').hidden=true;$('auth').hidden=false;$('account-email').textContent='';$('businesses').replaceChildren();$('branch').replaceChildren();$('branch-info').textContent='';$('branch-box').hidden=true;$('onboard').hidden=true;$('onboard').reset();selected='';businesses=[];branchList=[];}
 function setMode(next){mode=next;$('login-tab').setAttribute('aria-pressed',String(next==='login'));$('signup-tab').setAttribute('aria-pressed',String(next==='signup'));$('auth-title').textContent=next==='login'?'Inicia sesión':'Crea tu cuenta';$('auth-submit').textContent=next==='login'?'Iniciar sesión':'Registrarme';$('password').autocomplete=next==='login'?'current-password':'new-password';$('password').minLength=next==='signup'?8:1;$('password').value='';}
 async function run(task){if(busy)return;busy=true;document.querySelectorAll('button,input,select').forEach(e=>e.disabled=true);say('');try{await task();}catch{if(!api.hasSession()&&!$('account').hidden)clearAccount();say('No se pudo completar la operación. Verifica tus datos o vuelve a iniciar sesión.');}finally{busy=false;document.querySelectorAll('button,input,select').forEach(e=>e.disabled=false);production.syncControls();}}
 async function pick(id){clearSubscription();inventory.clear();production.clear();commerce.clear();finance.clear();selected='';branchList=[];$('branch-box').hidden=true;$('branch').replaceChildren();$('branch-info').textContent='';$('businesses').querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed','false'));const rows=await api.branches(id);selected=id;branchList=rows.filter(b=>b.active);$('businesses').querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.id===id)));for(const b of branchList){const option=document.createElement('option');option.value=b.id;option.textContent=b.name;$('branch').append(option);}$('branch-box').hidden=false;await showSubscription(id,rows);await showBranch();}
 async function showBranch(){inventory.clear();production.clear();commerce.clear();finance.clear();const b=branchList.find(b=>b.id===$('branch').value);$('branch-info').textContent=b?'Sucursal seleccionada: '+b.name:'No hay sucursales activas.';const m=businesses.find(x=>x.bakery_id===selected);if(b&&m){const scope={bakery:selected,branch:b.id,role:m.role,label:(m.bakeries?.name||'Negocio')+' · '+b.name};await inventory.open(scope);await production.open(scope);await commerce.open(scope);await finance.open(scope);}}
 async function load(){ clearSubscription();inventory.clear();production.clear();commerce.clear();finance.clear();$('businesses').replaceChildren();$('branch-box').hidden=true;$('onboard').hidden=true;selected='';branchList=[];businesses=await api.businesses();$('onboard').hidden=businesses.length!==0;for(const m of businesses){const b=document.createElement('button');b.type='button';b.className='business';b.dataset.id=m.bakery_id;b.setAttribute('aria-pressed','false');b.textContent=(m.bakeries?.name||'Negocio')+' · '+({owner:'Propietario',admin:'Administrador',operator:'Operario',viewer:'Consulta'}[m.role]||'Miembro');b.addEventListener('click',()=>run(()=>pick(m.bakery_id)));$('businesses').append(b);}if(businesses.length)await pick(businesses[0].bakery_id);}
 $('auth').hidden=false;setMode('login');
 $('login-tab').addEventListener('click',()=>setMode('login'));$('signup-tab').addEventListener('click',()=>setMode('signup'));
 $('auth-form').addEventListener('submit',e=>{e.preventDefault();const email=$('email').value.trim(),password=$('password').value;$('password').value='';run(async()=>{if(mode==='signup'){await api.signup(email,password);setMode('login');say('Si el registro está disponible, recibirás un correo de confirmación. Confirma tu correo e inicia sesión.');}else{const user=await api.login(email,password);$('account-email').textContent=user?.email||email;$('auth').hidden=true;$('account').hidden=false;await load();}});});
 $('onboard').addEventListener('submit',e=>{e.preventDefault();const name=$('bakery-name').value.trim(),branch=$('branch-name').value.trim();run(async()=>{if(!name||!branch){say('Escribe el nombre del negocio y la sucursal.');return;}await api.create(name,branch);$('onboard').reset();await load();say('Espacio de trabajo creado.');});});
 $('branch').addEventListener('change',()=>run(showBranch));$('reload').addEventListener('click',()=>run(load));
 $('logout').addEventListener('click',()=>run(async()=>{try{await api.logout();say('Sesión cerrada.');}catch{say('Se cerró el acceso local; no se confirmó la revocación remota.');}finally{clearAccount();setMode('login');}}));
}
if(typeof document!=='undefined'&&document.getElementById('auth-form'))init();
if(typeof module!=='undefined')module.exports={validateConfig,createApi};
