const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const {workspaceRoutes,resolveWorkspaceRoute,routeVisible}=require('../../frontend/dashboard/workspace-navigation.js');
const root=path.join(__dirname,'../..'),html=fs.readFileSync(path.join(root,'access.html'),'utf8'),css=fs.readFileSync(path.join(root,'assets/styles/portal.css'),'utf8');
assert.equal(Object.keys(workspaceRoutes).length,11);
for(const k of Object.keys(workspaceRoutes)){assert.ok(html.includes('data-nav="'+k+'"'));assert.ok([...html.matchAll(/data-route-part="([^"]+)"/g)].some(m=>routeVisible(m[1],k)));assert.equal(resolveWorkspaceRoute(k,true,true),k);}
assert.equal(resolveWorkspaceRoute('sales',false,false),'business');assert.equal(resolveWorkspaceRoute('subscription',false,true),'subscription');assert.equal(resolveWorkspaceRoute('subscription',false,false),'business');assert.equal(resolveWorkspaceRoute('__proto__',true,true),'home');assert.equal(routeVisible('purchases sales cash','reports'),false);
const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);assert.equal(new Set(ids).size,ids.length,'duplicate IDs');
for(const id of ['auth-form','businesses','branch','ingredient-form','movement-form','recipe-form','batch-form','purchase-form','sale-form','cash-open-form','cash-close-form','cash-entry-form','fin-chart','own-subscription'])assert.ok(ids.includes(id),id);
assert.match(css,/color-scheme:light/);assert.match(css,/\.route-off\{display:none!important\}/);assert.doesNotMatch(css,/prefers-color-scheme\s*:\s*dark/);
console.log('Workspace navigation: routes, scope gates, unique IDs and light theme passed');
