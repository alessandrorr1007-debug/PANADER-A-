'use strict';
// Operator-only configuration. Run from the repository with a scoped Management API token
// in the environment, never a frontend key or a token committed to Git.
const fs=require('node:fs');
const path=require('node:path');
const project='dptzjteotamddcoogdvd';
const endpoint='https://api.supabase.com/v1/projects/'+project+'/config/auth';
function buildEmailConfig(){
 const dir=path.join(__dirname,'../docs/installation/email-templates');
 const read=name=>fs.readFileSync(path.join(dir,name+'.html'),'utf8').trim();
 const config={mailer_autoconfirm:false,mailer_otp_length:6,mailer_subjects_confirmation:'Panadería SaaS | Confirma tu cuenta',mailer_subjects_recovery:'Panadería SaaS | Recupera tu contraseña',mailer_templates_confirmation_content:read('confirmation'),mailer_templates_recovery_content:read('recovery')};
 for(const key of ['mailer_templates_confirmation_content','mailer_templates_recovery_content']){
  const s=config[key];
  if(!s.includes('{{ .Token }}')||/ConfirmationURL|TokenHash|<a\b|href\s*=/i.test(s))throw Error('Invalid code-only email template');
 }
 return config;
}
async function configureEmail({token,apply=false,fetcher=fetch}){
 if(typeof token!=='string'||!token.trim())throw Error('Falta SUPABASE_ACCESS_TOKEN. Usa un token de Management API de alcance mínimo; no lo compartas.');
 const config=buildEmailConfig();
 const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
 async function request(method,body){
  const response=await fetcher(endpoint,{method,headers,body:body===undefined?undefined:JSON.stringify(body),redirect:'error',cache:'no-store'});
  if(!response.ok)throw Error('Management API: HTTP '+response.status);
  return method==='GET'?response.json():undefined;
 }
 if(apply)await request('PATCH',config);
 const live=await request('GET');
 // Never output the full Auth config (it can contain sensitive credentials).
 const mismatches=Object.keys(config).filter(k=>typeof config[k]==='string'?String(live[k]??'').trim()!==config[k]:live[k]!==config[k]);
 return {project,applied:apply,verified:mismatches.length===0,mismatches};
}
if(require.main===module){
 const args=process.argv.slice(2);
 if(args.length!==1||!['--check','--apply'].includes(args[0])){console.error('Uso: node scripts/configure-auth-email.cjs --check | --apply');process.exitCode=1;}
 else configureEmail({token:process.env.SUPABASE_ACCESS_TOKEN,apply:args[0]==='--apply'}).then(result=>{console.log(JSON.stringify(result,null,2));if(!result.verified)process.exitCode=1;}).catch(e=>{console.error(e.message);process.exitCode=1;});
}
module.exports={buildEmailConfig,configureEmail};
