const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const {workspaceRoutes,resolveWorkspaceRoute,routeVisible,workspacePermissions}=require('../../frontend/dashboard/workspace-navigation.js');
const root=path.join(__dirname,'../..'),html=fs.readFileSync(path.join(root,'access.html'),'utf8'),css=fs.readFileSync(path.join(root,'assets/styles/portal.css'),'utf8');
assert.equal(Object.keys(workspaceRoutes).length,13);
for(const k of Object.keys(workspaceRoutes)){assert.ok(html.includes('data-nav="'+k+'"'));assert.ok([...html.matchAll(/data-route-part="([^"]+)"/g)].some(m=>routeVisible(m[1],k)));assert.equal(resolveWorkspaceRoute(k,true,true),k);}
assert.equal(resolveWorkspaceRoute('sales',false,false),'business');assert.equal(resolveWorkspaceRoute('subscription',false,true),'subscription');assert.equal(resolveWorkspaceRoute('subscription',false,false),'business');assert.equal(resolveWorkspaceRoute('__proto__',true,true),'home');assert.equal(routeVisible('purchases sales cash','reports'),false);
const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);assert.equal(new Set(ids).size,ids.length,'duplicate IDs');
for(const id of ['auth-form','businesses','branch','ingredient-form','movement-form','recipe-form','batch-form','purchase-form','sale-form','cash-open-form','cash-close-form','cash-entry-form','fin-chart','own-subscription'])assert.ok(ids.includes(id),id);
assert.match(css,/color-scheme:light/);assert.match(css,/\.route-off\{display:none!important\}/);assert.doesNotMatch(css,/prefers-color-scheme\s*:\s*dark/);
console.log('Workspace navigation: routes, scope gates, unique IDs and light theme passed');

// Role-aware navigation and management areas. Visibility is not a replacement for RLS.
assert.deepEqual(workspacePermissions('admin',['sales'],true,true),['business','account','home','sales','catalog','orders']);
assert.deepEqual(workspacePermissions('admin',[],true,true),['business','account','home']);
assert.deepEqual(workspacePermissions('operator',['production','cash'],true,true),['business','account','home','production','cash']);
assert.deepEqual(workspacePermissions('owner',[],false,true),['business','account','subscription','team']);
assert.equal(workspacePermissions('owner',[],true,true).length,13);
assert.deepEqual(workspacePermissions(null,[],false,false),['business','account']);
assert.equal(resolveWorkspaceRoute('account',false,false),'account');assert.equal(resolveWorkspaceRoute('team',false,false),'business');
assert.match(html,/id="team-area"[^>]*data-route-part="team"/);
assert.match(html,/id="workspace-menu-toggle"[^>]*aria-controls="workspace-nav"/);
for(const route of ['reports','inventory','sales'])assert.match(html,new RegExp('data-overview-route="'+route+'"'));
console.log('Role UI: owner, employee, no permissions, mobile menu, scoped overview passed');
