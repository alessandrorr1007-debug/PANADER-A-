const assert=require('node:assert/strict');const {modulePermissions,employeePermissionLabels}=require('../../frontend/inventory/inventory-controller.js');const {createApi}=require('../../frontend/shared/api-client.js');
const sub={status:'trial',valid_until:'2030-01-01T00:00:00Z'},now=Date.parse('2026-11-27T00:00:00Z');
assert.equal(Object.keys(employeePermissionLabels).length,8);
assert.equal(modulePermissions({role:'owner'},sub,'cash','sales',now).manager,true);
assert.equal(modulePermissions({role:'admin',grants:['sales']},sub,'cash','sales',now).manager,false);
assert.equal(modulePermissions({role:'admin',grants:['sales']},sub,'cash','sales',now).movement,true);
assert.equal(modulePermissions({role:'admin'},sub,'cash','sales',now).movement,false);
assert.equal(modulePermissions({role:'admin',grants:['sales']},{...sub,status:'suspended'},'cash','sales',now).movement,false);
(async()=>{const calls=[],api=createApi({url:'https://example.supabase.co',key:'sb_publishable_test'},async(url,opts)=>{calls.push({url,opts});return {ok:true,status:200,json:async()=>url.includes('grant_type')?{access_token:'fake',user:{}}:[]};});await api.login('test@example.test','test-password');await api.inviteEmployee('b','e@example.test',['sales']);assert.deepEqual(JSON.parse(calls.at(-1).opts.body),{p_bakery:'b',p_email:'e@example.test',p_permissions:['sales']});await api.setEmployeePermissions('b','u',['cash']);assert.deepEqual(JSON.parse(calls.at(-1).opts.body),{p_bakery:'b',p_user:'u',p_permissions:['cash']});await api.myPermissions('b');assert.ok(calls.at(-1).url.endsWith('/my_permissions'));console.log('Employee permission UI and API checks passed');})().catch(e=>{console.error(e);process.exitCode=1});
