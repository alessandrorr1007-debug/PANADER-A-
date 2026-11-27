const assert=require('node:assert/strict');const {validateConfig,createApi}=require('../../frontend/shared/api-client.js');
(async()=>{
 const cfg=validateConfig({url:'https://example.supabase.co',publishableKey:'sb_publishable_test'});assert.ok(cfg);
 for(const url of ['http://example.supabase.co','https://example.supabase.co.evil.test','https://example.supabase.co/path','https://example.supabase.co?x=y'])assert.equal(validateConfig({url,publishableKey:'sb_publishable_test'}),null);
 assert.equal(validateConfig({url:cfg.url,publishableKey:'sb_secret_test'}),null);
 const calls=[];const api=createApi(cfg,async(url,opts)=>{calls.push({url,opts});return {ok:true,status:200,json:async()=>url.includes('grant_type')?{access_token:'token-test',user:{email:'demo@example.test'}}:[]};});
 await assert.rejects(api.businesses());assert.equal(calls.length,0);
 await api.signup('demo@example.test','password');assert.equal(calls[0].opts.headers.Authorization,undefined);assert.equal(api.hasSession(),false);
 await api.login('demo@example.test','password');assert.equal(api.hasSession(),true);
 await api.businesses();assert.equal(calls.at(-1).opts.headers.Authorization,'Bearer token-test');
 await api.branches('a&role=owner');assert.ok(calls.at(-1).url.includes('a%26role%3Downer'));
 await api.create('Aurora','Centro');assert.deepEqual(JSON.parse(calls.at(-1).opts.body),{p_name:'Aurora',p_branch:'Centro'});
 await api.logout();assert.equal(api.hasSession(),false);await assert.rejects(api.businesses());
 assert.ok(calls.every(c=>c.opts.redirect==='error'&&c.opts.cache==='no-store'));
 console.log('Pruebas de configuración y cliente de acceso aprobadas');
})().catch(e=>{console.error(e);process.exitCode=1});
