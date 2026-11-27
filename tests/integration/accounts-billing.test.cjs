const assert=require('node:assert/strict');const {createApi}=require('../../frontend/shared/api-client.js');
(async()=>{const calls=[];const api=createApi({url:'https://example.supabase.co',key:'sb_publishable_test'},async(url,opts)=>{calls.push({url,opts});return {ok:true,status:200,json:async()=>url.includes('grant_type')?{access_token:'test'}:true};});
await assert.rejects(api.registerSession('Caja'));await api.login('owner@example.test','pass');
const cases=[
 ['registerSession',['Caja'],'register_portal_session',{p_label:'Caja'}],['sessionStatus',[],'portal_session_status',{}],
 ['sessions',[],'my_portal_sessions',{}],['revokeSession',['s'],'revoke_portal_session',{p_session:'s'}],
 ['inviteWorker',['a','w@example.test','operator'],'invite_worker',{p_bakery:'a',p_email:'w@example.test',p_role:'operator'}],
 ['myInvitations',[],'my_invitations',{}],['acceptInvitation',['i'],'accept_invitation',{p_invite:'i'}],
 ['teamMembers',['a'],'team_members',{p_bakery:'a'}],['teamInvitations',['a'],'team_invitations',{p_bakery:'a'}],
 ['revokeInvitation',['a','i'],'revoke_invitation',{p_bakery:'a',p_invite:'i'}],['removeWorker',['a','u'],'remove_worker',{p_bakery:'a',p_user:'u'}],
 ['billingOptions',[],'billing_options',{}],['billingPayments',['a'],'my_billing_payments',{p_bakery:'a'}],
 ['submitPayment',['a','q','starter','month','yape','ABCD',29],'submit_billing_payment',{p_bakery:'a',p_request:'q',p_plan:'starter',p_period:'month',p_method:'yape',p_reference:'ABCD',p_amount:29}],
 ['pendingPayments',[],'pending_billing_payments',{}],['reviewPayment',['p',true,'verified'],'review_billing_payment',{p_payment:'p',p_approve:true,p_note:'verified'}],
 ['setBillingPrice',['starter','month',29,true],'set_billing_price',{p_plan:'starter',p_period:'month',p_amount:29,p_enabled:true}],
 ['setBillingMethod',['yape','Fixture',true],'set_billing_method',{p_method:'yape',p_instructions:'Fixture',p_enabled:true}]];
for(const [name,args,rpc,body] of cases){await api[name](...args);const c=calls.at(-1);assert.ok(c.url.endsWith('/rpc/'+rpc));assert.equal(c.opts.method,'POST');assert.equal(c.opts.headers.Authorization,'Bearer test');assert.deepEqual(JSON.parse(c.opts.body),body);}
console.log(cases.length+' accounts and billing RPC contracts passed');
})().catch(e=>{console.error(e);process.exitCode=1});
