const assert=require('node:assert/strict');const {createApi}=require('../../frontend/shared/api-client.js');
(async()=>{const calls=[];const api=createApi({url:'https://example.supabase.co',key:'sb_publishable_test'},async(url,opts)=>{calls.push({url,opts});const data=url.endsWith('/challenge')?{id:'challenge'}:url.endsWith('/verify')||url.includes('grant_type')?{access_token:'new-token',user:{id:'u'}}:url.endsWith('/factors')?{id:'factor',totp:{secret:'TEST'}}:{};return {ok:true,status:200,json:async()=>data};});
await api.resendConfirmation('a@example.test');assert.deepEqual(JSON.parse(calls.at(-1).opts.body),{type:'signup',email:'a@example.test'});
await api.recover('a@example.test');assert.ok(calls.at(-1).url.endsWith('/recover'));
await assert.rejects(api.verifyEmail('a@example.test','bad','recovery'));
await api.verifyEmail('a@example.test','123456','recovery');assert.deepEqual(JSON.parse(calls.at(-1).opts.body),{email:'a@example.test',token:'123456',type:'recovery'});
await api.authRequirements();assert.equal(calls.at(-1).opts.headers.Authorization,'Bearer new-token');
await api.enrollTotp();assert.equal(JSON.parse(calls.at(-1).opts.body).factor_type,'totp');
await api.verifyTotp('factor','123456');assert.deepEqual(JSON.parse(calls.at(-1).opts.body),{challenge_id:'challenge',code:'123456'});
await api.updatePassword('test-long-password');assert.equal(calls.at(-1).opts.method,'PUT');await api.logoutAll();assert.equal(api.hasSession(),false);
console.log('Auth email, recovery, TOTP and logout API contracts passed');
})().catch(e=>{console.error(e);process.exitCode=1});

// The public signup is ordinary identity registration; admin portal is login-only.
{const fs=require('node:fs'),path=require('node:path');const root=path.resolve(__dirname,'../..');const read=p=>fs.readFileSync(path.join(root,p),'utf8');const admin=read('admin.html'),flow=read('frontend/auth/auth-flow.js'),access=read('frontend/auth/access-controller.js');require('node:assert/strict').doesNotMatch(admin,/signup-tab|Registrarme|Para crear una cuenta usa/);require('node:assert/strict').match(flow,/if\(admin&&!requirements\.platform_admin\)/);require('node:assert/strict').match(flow,/minLength:6/);require('node:assert/strict').match(access,/next==='signup'\?6:1/);}

// Role routing follows the server after registration, not an email, URL, or metadata.
(async()=>{const {resolveAuthenticatedWorkspace}=require('../../frontend/auth/access-controller.js');for(const role of [true,false]){const events=[];const api={registerSession:async label=>{assert.equal(label,'Equipo');events.push('session');},authRequirements:async()=>{events.push('role');return {platform_admin:role};},sessionStatus:async()=>{events.push('status');return true;}};assert.equal(await resolveAuthenticatedWorkspace(api,'Equipo'),role?'platform':'business');assert.deepEqual(events,['session','role','status']);}const api={registerSession:async()=>{},authRequirements:async()=>({platform_admin:true}),sessionStatus:async()=>false};await assert.rejects(resolveAuthenticatedWorkspace(api,'Equipo'));await assert.rejects(resolveAuthenticatedWorkspace({...api,registerSession:async()=>{throw Error('MFA requerido');}},'Equipo'));await assert.rejects(resolveAuthenticatedWorkspace({...api,authRequirements:async()=>({platform_admin:'true'})},'Equipo'));console.log('Unified login: trusted role, MFA/session gates and invalid roles passed');})().catch(e=>{console.error(e);process.exitCode=1});
