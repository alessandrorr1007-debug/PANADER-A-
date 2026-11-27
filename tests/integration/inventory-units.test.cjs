const assert=require('node:assert/strict');const {baseQuantity,allowedUnits}=require('../../frontend/inventory/inventory-controller.js');
assert.deepEqual(allowedUnits('kg'),['kg','g']);assert.equal(baseQuantity('500','g','kg'),'0.5');assert.equal(baseQuantity('1250','ml','L'),'1.25');assert.equal(baseQuantity('0.001','kg','kg'),'0.001');assert.equal(baseQuantity('1','g','kg'),'0.001');assert.equal(baseQuantity('0','ml','L',true),'0');assert.equal(baseQuantity('99999999999','kg','kg'),'99999999999');
for(const [q,u,b] of [['0.5','g','kg'],['1','ml','kg'],['-1','kg','kg'],['0','kg','kg'],['1e3','g','kg'],['100000000000','kg','kg'],['0.0001','kg','kg']])assert.throws(()=>baseQuantity(q,u,b));
console.log('Exact unit conversions and incompatible/invalid quantities passed');
