'use strict';
const workspaceRoutes=Object.freeze({"home":"Resumen","inventory":"Almacén e insumos","production":"Recetas y producción","purchases":"Compras","sales":"Punto de venta","cash":"Caja","reports":"Reportes","subscription":"Mi suscripción","business":"Mi negocio"});
function resolveWorkspaceRoute(route,ready,hasBusiness){if(!Object.prototype.hasOwnProperty.call(workspaceRoutes,route))route='home';if(route==='business')return route;if(route==='subscription')return hasBusiness?route:'business';return ready?route:'business';}
function routeVisible(routes,route){return String(routes).split(/\s+/).includes(route);}
function createWorkspaceNavigation(){
 const $=id=>document.getElementById(id),shell=$('workspace-shell');let ready=false,hasBusiness=false,route='business';
 const text=(id,value)=>{$(id).textContent=value;};
 function sync(){
 for(const [target,content,source] of [['overview-revenue','finance-content','fin-revenue'],['overview-stock','inventory-content','inv-total'],['overview-alert','inventory-content','inv-low'],['overview-finished','commerce-content','com-stock']])text(target,ready&&!$(content).hidden?$(source).textContent:'—');
 text('overview-period',ready&&!$('finance-content').hidden?$('fin-range').textContent:'Reportes aún no disponibles.');
 $('subscription-empty').hidden=!$('own-subscription').hidden;
 }
 function show(next,focus=false){
 route=resolveWorkspaceRoute(next,ready,hasBusiness);shell.dataset.activeRoute=route;
 for(const el of shell.querySelectorAll('[data-route-part]'))el.classList.toggle('route-off',!routeVisible(el.dataset.routePart,route));
 for(const b of shell.querySelectorAll('[data-nav]')){if(b.dataset.nav===route)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');b.disabled=resolveWorkspaceRoute(b.dataset.nav,ready,hasBusiness)!==b.dataset.nav;}
 text('workspace-title',workspaceRoutes[route]);if(focus){$('workspace-title').focus({preventScroll:true});window.scrollTo(0,0);}sync();
 }
 function setContext({available=false,business=false,label='',reset=false}={}){ready=available;hasBusiness=business;text('workspace-context',label||'Selecciona tu negocio');show(reset?(ready?'home':'business'):route);}
 for(const b of shell.querySelectorAll('[data-nav],[data-go]'))b.addEventListener('click',()=>show(b.dataset.nav||b.dataset.go,true));
 setContext();return {setContext,sync,restore:()=>show(route)};
}
if(typeof module!=='undefined')module.exports={resolveWorkspaceRoute,routeVisible,workspaceRoutes};
