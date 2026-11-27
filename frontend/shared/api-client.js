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
 const useToken=data=>{if(!data?.access_token)throw new Error('Sesión no disponible');token=data.access_token;return data.user;};
 const factorPath=id=>'/auth/v1/factors/'+encodeURIComponent(id);
 return {authUser:()=>request('/auth/v1/user','GET',undefined,true),
 authRequirements:()=>rpc('auth_requirements',{}),
 resendConfirmation:email=>request('/auth/v1/resend','POST',{type:'signup',email}),
 recover:email=>request('/auth/v1/recover','POST',{email}),
 async verifyEmail(email,code,type){if(!['signup','recovery'].includes(type)||!/^\d{6}$/.test(code))throw Error('Código inválido');token=null;return useToken(await request('/auth/v1/verify','POST',{email,token:code,type}));},
 updatePassword:password=>request('/auth/v1/user','PUT',{password},true),
 async logoutAll(){try{if(token)await request('/auth/v1/logout?scope=global','POST',undefined,true);}finally{token=null;}},
 enrollTotp:()=>request('/auth/v1/factors','POST',{factor_type:'totp',issuer:'Panaderia SaaS'},true),
 removeFactor:id=>request(factorPath(id),'DELETE',undefined,true),
 async verifyTotp(id,code){if(!/^\d{6}$/.test(code))throw Error('Código inválido');const challenge=await request(factorPath(id)+'/challenge','POST',{},true);if(!challenge?.id)throw Error('Desafío inválido');const data=await request(factorPath(id)+'/verify','POST',{challenge_id:challenge.id,code},true);useToken(data);},
 signup:(email,password)=>request('/auth/v1/signup','POST',{email,password}),
 async login(email,password){token=null;const data=await request('/auth/v1/token?grant_type=password','POST',{email,password});if(!data?.access_token)throw new Error('Sesión no disponible');token=data.access_token;return data.user;},
 async logout(){try{if(token)await request('/auth/v1/logout?scope=local','POST',undefined,true);}finally{token=null;}},
 hasSession:()=>!!token,
 businesses:()=>request('/rest/v1/bakery_members?select=bakery_id,role,bakeries(id,name)&order=bakery_id','GET',undefined,true),
 branches:id=>request('/rest/v1/branches?select=id,name,active&bakery_id=eq.'+encodeURIComponent(id)+'&order=name','GET',undefined,true),
 create:(name,branch)=>request('/rest/v1/rpc/create_initial_bakery','POST',{p_name:name,p_branch:branch},true),
 ingredients:(id,cursor='')=>request('/rest/v1/ingredients?select=id,name,unit,reference_cost,active&bakery_id=eq.'+encodeURIComponent(id)+'&order=id.asc&limit=200'+(cursor?'&id=gt.'+encodeURIComponent(cursor):''),'GET',undefined,true),
 balances:(id,branch,cursor='')=>request('/rest/v1/stock_balances?select=ingredient_id,quantity,minimum&bakery_id=eq.'+encodeURIComponent(id)+'&branch_id=eq.'+encodeURIComponent(branch)+'&order=ingredient_id.asc&limit=200'+(cursor?'&ingredient_id=gt.'+encodeURIComponent(cursor):''),'GET',undefined,true),
 costHistory:(id,branch)=>list('ingredient_cost_history','select=id,ingredient_id,purchased_quantity,purchased_unit_cost,previous_cost,new_cost,created_at'+scoped(id,branch)+'&order=created_at.desc,id.desc&limit=30'),
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
 changeSubscription:(id,plan,status,until)=>rpc('set_subscription',{p_bakery:id,p_plan:plan,p_status:status,p_valid_until:until}),
 trialEligible:()=>rpc('trial_eligible',{}),
 registerSession:label=>rpc('register_portal_session',{p_label:label}), sessionStatus:()=>rpc('portal_session_status',{}),
 sessions:()=>rpc('my_portal_sessions',{}),revokeSession:id=>rpc('revoke_portal_session',{p_session:id}),
 inviteWorker:(id,email,role)=>rpc('invite_worker',{p_bakery:id,p_email:email,p_role:role}),myInvitations:()=>rpc('my_invitations',{}),
 acceptInvitation:id=>rpc('accept_invitation',{p_invite:id}),teamMembers:id=>rpc('team_members',{p_bakery:id}),teamInvitations:id=>rpc('team_invitations',{p_bakery:id}),
 revokeInvitation:(id,invite)=>rpc('revoke_invitation',{p_bakery:id,p_invite:invite}),removeWorker:(id,user)=>rpc('remove_worker',{p_bakery:id,p_user:user}),
 billingOptions:()=>rpc('billing_options',{}),billingPayments:id=>rpc('my_billing_payments',{p_bakery:id}),
 submitPayment:(id,req,plan,period,method,reference,amount)=>rpc('submit_billing_payment',{p_bakery:id,p_request:req,p_plan:plan,p_period:period,p_method:method,p_reference:reference,p_amount:amount}),
 pendingPayments:()=>rpc('pending_billing_payments',{}),reviewPayment:(id,approve,note)=>rpc('review_billing_payment',{p_payment:id,p_approve:approve,p_note:note}),
 setBillingPrice:(plan,period,amount,enabled)=>rpc('set_billing_price',{p_plan:plan,p_period:period,p_amount:amount,p_enabled:enabled}),
 setBillingMethod:(method,instructions,enabled)=>rpc('set_billing_method',{p_method:method,p_instructions:instructions,p_enabled:enabled})};
}
if(typeof module!=='undefined')module.exports={validateConfig,createApi};
