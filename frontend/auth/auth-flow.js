'use strict';
// No secret, password, or token is persisted. All auth requests use the project's Auth API.
function createAuthFlow({api,run,root,loginForm,notify,admin=false}){
 const node=(tag,text)=>{const el=document.createElement(tag);if(text)el.textContent=text;return el;};
 let current=null;
 function clear(){root.replaceChildren();root.hidden=true;loginForm.hidden=false;current=null;}
 function show(title,detail){root.replaceChildren();root.hidden=false;loginForm.hidden=true;const heading=node('h3',title);heading.tabIndex=-1;root.append(heading,node('p',detail));heading.focus();}
 function button(label,action){const b=node('button',label);b.type='button';b.addEventListener('click',()=>run(async()=>{try{await action();}catch{notify('No se pudo completar este paso. Comprueba el código, la conexión o vuelve a ingresar.');}}));root.append(b);return b;}
 function field(form,label,type,options={}){const l=node('label',label),i=node('input');i.type=type;i.required=true;Object.assign(i,options);l.append(i);form.append(l);return i;}
 function form(label,action){const f=node('form'),b=node('button',label);b.className='primary';b.type='submit';root.append(f);f.addEventListener('submit',e=>{e.preventDefault();run(async()=>{try{await action();}catch{notify('No se pudo completar este paso. Comprueba tus datos o solicita un nuevo código.');}});});return {f,b};}
 async function cancel(){try{await api.logout();}catch{}clear();notify('Vuelve a iniciar sesión.');}
 function cancelButton(){button('Cancelar',cancel);}
 async function finish(next){clear();try{await next();}catch(e){try{await api.logout();}catch{}clear();throw e;}}
 function codeEntry(title,detail,handler){show(title,detail);const {f,b}=form('Verificar',async()=>{const code=i.value.trim();i.value='';if(!/^\d{6}$/.test(code))throw Error();await handler(code);});const i=field(f,'Código de 6 dígitos','text',{inputMode:'numeric',maxLength:6,minLength:6,autocomplete:'one-time-code',pattern:'[0-9]{6}'});f.append(b);cancelButton();}
 async function mfa(next,{offer=true,recovery=false,enable=false}={}){
 const [requirements,user]=await Promise.all([api.authRequirements(),api.authUser()]);
 if(admin&&!requirements.platform_admin)throw Error('No autorizado');
 const all=Array.isArray(user.factors)?user.factors:[],verified=all.filter(x=>x.status==='verified');
 const totp=verified.filter(x=>x.factor_type==='totp');
 if(requirements.has_factor||verified.length){
 if(!totp.length)throw Error('Método MFA no compatible');
 show('Verificación en dos pasos','Introduce el código temporal de tu aplicación autenticadora.');
 const {f,b}=form('Verificar e ingresar',async()=>{const v=code.value.trim();code.value='';await api.verifyTotp(select.value,v);await finish(next);});
 const label=node('label','Autenticador'),select=node('select');for(const factor of totp){const o=node('option',factor.friendly_name||'Autenticador');o.value=factor.id;select.append(o);}label.append(select);f.append(label);
 const code=field(f,'Código de 6 dígitos','text',{inputMode:'numeric',maxLength:6,minLength:6,autocomplete:'one-time-code',pattern:'[0-9]{6}'});f.append(b);cancelButton();return;
 }
 if(recovery){await finish(next);return;}
 const required=admin||requirements.required;
 async function enroll(){for(const f of all.filter(x=>x.status==='unverified'&&x.factor_type==='totp'))await api.removeFactor(f.id);
 const enrollment=await api.enrollTotp();if(!enrollment?.id||!enrollment?.totp?.secret)throw Error('No se pudo configurar');
 show('Configurar autenticador','Agrega una cuenta basada en tiempo (TOTP) en tu aplicación autenticadora. Escribe la clave a continuación. No la compartas.');
 const secret=node('code',enrollment.totp.secret);secret.className='auth-secret';root.append(secret);
 const {f,b}=form('Activar verificación',async()=>{const v=code.value.trim();code.value='';await api.verifyTotp(enrollment.id,v);secret.textContent='';await finish(next);});
 const code=field(f,'Código generado por tu autenticador','text',{inputMode:'numeric',maxLength:6,minLength:6,autocomplete:'one-time-code',pattern:'[0-9]{6}'});f.append(b);cancelButton();}
 if(required||enable){await enroll();return;}
 if(offer){show('Protege tu cuenta','Puedes activar la autenticación en dos pasos sin costo. Una vez configurada se exigirá al ingresar.');button('Configurar autenticador',enroll);button('Continuar sin segundo factor',()=>finish(next));cancelButton();return;}
 await finish(next);
 }
 function confirmation(email){codeEntry('Confirma tu correo','Introduce el código enviado a tu correo. Si no llega, comprueba spam o solicita otro.',async code=>{await api.verifyEmail(email,code,'signup');try{await api.logout();}catch{}clear();notify('Correo confirmado. Inicia sesión con tu contraseña.');});button('Reenviar código',async()=>{await api.resendConfirmation(email);notify('Si corresponde, se enviará otro código.');});}
 function reset(){show('Recuperar contraseña','Escribe tu correo. Si la cuenta existe y admite recuperación, recibirás un código.');
 const {f,b}=form('Enviar código',async()=>{const address=email.value.trim();await api.recover(address);codeEntry('Código de recuperación','Introduce el código recibido por correo.',async code=>{await api.verifyEmail(address,code,'recovery');await mfa(async()=>{show('Nueva contraseña','Usa al menos 6 caracteres. Se intentará cerrar todas las sesiones al cambiarla.');const {f,b}=form('Guardar nueva contraseña',async()=>{const pw=p.value,again=c.value;p.value='';c.value='';if(pw!==again||pw.length<6||pw.length>128)throw Error();await api.updatePassword(pw);try{await api.logoutAll();notify('Contraseña actualizada. Inicia sesión nuevamente.');}catch{notify('Contraseña actualizada. No se confirmó el cierre remoto de todas las sesiones.');}clear();});const p=field(f,'Nueva contraseña','password',{minLength:6,maxLength:128,autocomplete:'new-password'}),c=field(f,'Repetir contraseña','password',{minLength:6,maxLength:128,autocomplete:'new-password'});f.append(b);cancelButton();},{recovery:true,offer:false});});});const email=field(f,'Correo electrónico','email',{autocomplete:'email',maxLength:254});f.append(b);cancelButton();}
 function requestConfirmation(){show('Confirmar correo','Escribe el correo con el que te registraste.');const {f,b}=form('Enviar código',async()=>{const address=e.value.trim();await api.resendConfirmation(address);confirmation(address);});const e=field(f,'Correo electrónico','email',{autocomplete:'email',maxLength:254});f.append(b);cancelButton();}
 return {clear,mfa,confirmation,reset,requestConfirmation};
}
