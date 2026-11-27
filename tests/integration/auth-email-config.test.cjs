'use strict';
const assert=require('node:assert/strict');
const {buildEmailConfig,configureEmail}=require('../../scripts/configure-auth-email.cjs');
(async()=>{
 const config=buildEmailConfig();
 assert.equal(config.mailer_autoconfirm,false);assert.equal(config.mailer_otp_length,6);
 assert.notEqual(config.mailer_subjects_confirmation,config.mailer_subjects_recovery);
 for(const k of ['mailer_templates_confirmation_content','mailer_templates_recovery_content']){assert.match(config[k],/\{\{ \.Token \}\}/);assert.doesNotMatch(config[k],/ConfirmationURL|TokenHash|<a\b|href\s*=/i);}
 let state={...config,mailer_templates_confirmation_content:'old'},calls=[];
 const fetcher=async(url,opts)=>{calls.push({url,method:opts.method});assert.equal(url,'https://api.supabase.com/v1/projects/dptzjteotamddcoogdvd/config/auth');assert.equal(opts.headers.Authorization,'Bearer mock-management-token');if(opts.method==='PATCH'){assert.deepEqual(JSON.parse(opts.body),config);state={...state,...JSON.parse(opts.body)};}return {ok:true,status:200,json:async()=>({...state,smtp_pass:'never-return-this'})};};
 const check=await configureEmail({token:'mock-management-token',fetcher});assert.equal(check.verified,false);assert.deepEqual(check.mismatches,['mailer_templates_confirmation_content']);assert.deepEqual(calls.map(c=>c.method),['GET']);
 calls=[];const result=await configureEmail({token:'mock-management-token',apply:true,fetcher});assert.equal(result.verified,true);assert.deepEqual(calls.map(c=>c.method),['PATCH','GET']);assert.doesNotMatch(JSON.stringify(result),/never-return-this|mock-management-token/);
 await assert.rejects(configureEmail({token:'',fetcher}));await assert.rejects(configureEmail({token:'mock-management-token',fetcher:async()=>({ok:false,status:403})}),/HTTP 403/);
 console.log('Auth email configuration: OTP-only templates, distinct subjects, explicit PATCH, verification and redaction passed');
})().catch(e=>{console.error(e);process.exitCode=1;});
