const assert=require('node:assert/strict');const {effectiveStatus,customerSummary,filterCustomers,subscriptionDraft}=require('../../frontend/admin/admin-controller.js');const {createApi}=require('../../frontend/shared/api-client.js');
(async()=>{
 const now=Date.parse('2026-11-27T12:00:00Z'),plans=[{code:'starter'},{code:'growth'}];
 const a={bakery_id:'a',name:'Aurora',plan_code:'starter',status:'trial',valid_until:'2026-11-28T00:00:00Z'},b={...a,bakery_id:'b',name:'Trigal',status:'active',valid_until:'2026-11-27T12:00:00Z'},c={...a,bakery_id:'c',name:'Molino',status:'suspended'};
 assert.equal(effectiveStatus(a,now),'trial');assert.equal(effectiveStatus(b,now),'expired');assert.equal(effectiveStatus(c,now),'suspended');
 assert.deepEqual(customerSummary([a,b,c],now),{total:3,active:0,trial:1,expired:1,suspended:1,cancelled:0});
 assert.deepEqual(filterCustomers([a,b,c],'trig','expired','starter',now),[b]);
 assert.deepEqual(subscriptionDraft(a,'growth','active','2026-11-30',plans,now),{plan:'growth',status:'active',until:'2026-12-01T05:00:00.000Z'});
 assert.equal(subscriptionDraft(a,'starter','suspended','',plans,now).until,a.valid_until);
 for(const args of [['starter','active','2026-02-30'],['starter','active','2026-11-26'],['fake','active','2026-12-01'],['starter','fake','']])assert.throws(()=>subscriptionDraft(a,...args,plans,now));
 assert.throws(()=>subscriptionDraft(b,'starter','active','',plans,now));
 const calls=[];const api=createApi({url:'https://example.supabase.co',key:'sb_publishable_test'},async(url,opts)=>{calls.push({url,opts});return {ok:true,status:200,json:async()=>url.includes('grant_type')?{access_token:'test'}:[]};});
 await assert.rejects(api.customers());await api.login('test@example.test','pass');
 await api.customers('a&x=1');assert.ok(calls.at(-1).url.includes('bakery_id=gt.a%26x%3D1'));assert.equal(calls.at(-1).opts.method,'POST');assert.equal(calls.at(-1).opts.body,'{}');
 await api.plans();assert.ok(calls.at(-1).url.includes('/saas_plans?'));
 await api.subscription('a');assert.ok(calls.at(-1).url.includes('select=plan_code,status,valid_until'));
 await api.changeSubscription('a','growth','active','2026-12-01T05:00:00Z');assert.deepEqual(JSON.parse(calls.at(-1).opts.body),{p_bakery:'a',p_plan:'growth',p_status:'active',p_valid_until:'2026-12-01T05:00:00Z'});
 assert.ok(calls.slice(1).every(c=>c.opts.headers.Authorization==='Bearer test'));
 await api.logout();await assert.rejects(api.changeSubscription('a','growth','active','2026-12-01T05:00:00Z'));
 const denied=createApi({url:'https://example.supabase.co',key:'sb_publishable_test'},async(url)=>url.includes('grant_type')?{ok:true,status:200,json:async()=>({access_token:'ordinary'})}:{ok:false,status:403});await denied.login('ordinary@example.test','pass');await assert.rejects(denied.customers());
 console.log('Admin integration: status, filters, expiration, authorization response and HTTP contracts passed');
})().catch(e=>{console.error(e);process.exitCode=1});

{const fs=require('node:fs'),path=require('node:path'),{resolvePlatformSection}=require('../../frontend/admin/admin-controller.js');const html=fs.readFileSync(path.join(__dirname,'../../access.html'),'utf8'),css=fs.readFileSync(path.join(__dirname,'../../assets/styles/portal.css'),'utf8');const template=html.match(/<template id="platform-workspace-template">([\s\S]*?)<\/template>/)[1];for(const key of ['overview','customers','billing','payments']){assert.equal(resolvePlatformSection(key),key);assert.ok(template.includes('data-platform-nav="'+key+'"'));assert.ok(template.includes('data-platform-section="'+key+'"'));assert.ok(template.includes('aria-controls="platform-'+key+'"'));}assert.equal(resolvePlatformSection('__proto__'),'overview');assert.equal(resolvePlatformSection(null),'overview');assert.match(template,/<textarea id="method-instructions"/);assert.match(template,/id="admin-empty"/);assert.match(css,/\.platform-client-table td::before/);assert.doesNotMatch(html.replace(/<template id="platform-workspace-template">[\s\S]*?<\/template>/,''),/data-platform-nav=/);console.log('Platform UI: navigation, mobile table, empty states and private mount passed');}
