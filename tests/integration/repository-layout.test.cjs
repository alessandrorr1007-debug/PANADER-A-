const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const exists=p=>assert.ok(fs.existsSync(path.join(root,p)),p);
for(const p of ['index.html','access.html','admin.html']){
 const html=read(p);
 for(const m of html.matchAll(/(?:src|href)="([^"]+)"/g)){const ref=m[1];if(/^(?:https?:|#|mailto:|data:)/.test(ref))continue;exists(ref);}
 for(const m of html.matchAll(/<script[^>]+src="([^"]+)"/g))new Function(read(m[1]));
}
const access=read('access.html'),admin=read('admin.html');
assert.ok(access.indexOf('frontend/shared/api-client.js')<access.indexOf('frontend/auth/access-controller.js'));
assert.ok(admin.indexOf('frontend/shared/api-client.js')<admin.indexOf('frontend/admin/admin-controller.js'));
assert.ok(!admin.includes('access-controller.js'));
assert.ok(!/<script>/.test(read('index.html')));
for(const p of ['access.js','admin.js','config.js','access.css','inventory.js','production.js','commerce.js','finance.js','workspace.js','database'])assert.ok(!fs.existsSync(path.join(root,p)),p+' should be moved');
const workflow=read('.github/workflows/verification.yml');
for(const m of workflow.matchAll(/(?:-f |node )(tests\/[\w/.-]+|backend\/[\w/.-]+)/g))exists(m[1]);
for(const m of read('README.md').matchAll(/\]\((docs\/[^)]+)\)/g))exists(m[1]);
assert.equal(require('../../frontend/shared/api-client.js').validateConfig({url:'',publishableKey:''}),null);
console.log('Repository structure, relative paths, script order and CI files passed');
