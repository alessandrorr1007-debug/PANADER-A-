const assert=require('node:assert/strict');const {localBusinessDate,reportDays,moneyCents,summarizeFinance}=require('../../frontend/cash-reports/finance-controller.js');const {createApi}=require('../../frontend/shared/api-client.js');
(async()=>{
 assert.equal(localBusinessDate(new Date('2026-11-28T03:00:00Z')),'2026-11-27');const days=reportDays(7,new Date('2026-11-28T03:00:00Z'));assert.equal(days[0],'2026-11-21');assert.equal(days.at(-1),'2026-11-27');assert.equal(reportDays(90).length,90);assert.throws(()=>reportDays(100));
 assert.equal(moneyCents('-0.01'),-1n);assert.equal(moneyCents('123.4'),12340n);assert.throws(()=>moneyCents('1.234'));
 const r=summarizeFinance(days,[{business_date:days[0],revenue:'10.01',units_sold:'3',sale_count:2,estimated_ingredient_cost:'12.02',estimated_ingredient_margin:'-2.01'}],[{business_date:days[1],received_cost:'5.20'}]);assert.equal(r.totals.revenue,1001n);assert.equal(r.totals.margin,-201n);assert.equal(r.totals.purchases,520n);assert.equal(r.totals.units,3n);assert.equal(r.rows[6].revenue,0n);
 const calls=[];const api=createApi({url:'https://example.supabase.co',key:'sb_publishable_test'},async(url,opts)=>{calls.push({url,opts});return {ok:true,status:200,json:async()=>url.includes('grant_type')?{access_token:'test'}:[]};});
 await assert.rejects(api.cashShifts('a','b'));await api.login('test@example.test','pass');
 await api.cashShifts('a','b');assert.ok(calls.at(-1).url.includes('branch_id=eq.b'));await api.cashEntries('a','s&x=1');assert.ok(calls.at(-1).url.includes('shift_id=eq.s%26x%3D1'));
 await api.dailySales('a','b',days[0],days.at(-1),days[1]);assert.ok(calls.at(-1).url.includes('business_date=gte.2026-11-21&business_date=lte.2026-11-27'));assert.ok(calls.at(-1).url.includes('business_date=gt.2026-11-22'));
 await api.dailyPurchases('a','b',days[0],days.at(-1));assert.ok(calls.at(-1).url.includes('daily_purchase_summary'));
 await api.addCashEntry('a','b','s','q','out',3.5,'Compra');assert.deepEqual(JSON.parse(calls.at(-1).opts.body),{p_bakery:'a',p_branch:'b',p_shift:'s',p_request:'q',p_direction:'out',p_amount:3.5,p_reason:'Compra'});
 assert.ok(calls.slice(1).every(c=>c.opts.headers.Authorization==='Bearer test'));console.log('Finance integration: date boundaries, totals, negative margin and API contracts passed');
})().catch(e=>{console.error(e);process.exitCode=1});
