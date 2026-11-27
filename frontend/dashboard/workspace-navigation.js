'use strict';
const workspaceRoutes=Object.freeze({"home":"Resumen","inventory":"Almacén e insumos","production":"Recetas y producción","purchases":"Compras","sales":"Punto de venta","catalog":"Catálogo","orders":"Pedidos y clientes","cash":"Caja","reports":"Reportes","subscription":"Mi suscripción","business":"Mi negocio"});
function resolveWorkspaceRoute(route,ready,hasBusiness){if(!Object.prototype.hasOwnProperty.call(workspaceRoutes,route))route='home';if(route==='business')return route;if(route==='subscription')return hasBusiness?route:'business';return ready?route:'business';}
function routeVisible(routes,route){return String(routes).split(/\s+/).includes(route);}
function createWorkspaceNavigation(){
 const $=id=>document.getElementById(id),shell=$('workspace-shell');let ready=false,hasBusiness=false,route='business',allowed=new Set(Object.keys(workspaceRoutes));
 const text=(id,value)=>{$(id).textContent=value;};
 function sync(){
 for(const [target,content,source] of [['overview-revenue','finance-content','fin-revenue'],['overview-stock','inventory-content','inv-total'],['overview-alert','inventory-content','inv-low'],['overview-finished','commerce-content','com-stock']])text(target,ready&&allowed.has(target==='overview-revenue'?'reports':target==='overview-finished'?'sales':'inventory')&&!$(content).hidden?$(source).textContent:'—');
 text('overview-period',ready&&allowed.has('reports')&&!$('finance-content').hidden?$('fin-range').textContent:'Reportes aún no disponibles.');
 $('subscription-empty').hidden=!$('own-subscription').hidden;
 }
 function availableRoute(next){const resolved=resolveWorkspaceRoute(next,ready,hasBusiness);return allowed.has(resolved)?resolved:'business';}
 function show(next,focus=false){
 route=availableRoute(next);shell.dataset.activeRoute=route;
 for(const el of shell.querySelectorAll('[data-route-part]'))el.classList.toggle('route-off',!routeVisible(el.dataset.routePart,route));
 for(const b of shell.querySelectorAll('[data-nav]')){if(b.dataset.nav===route)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');b.hidden=!allowed.has(b.dataset.nav);b.disabled=availableRoute(b.dataset.nav)!==b.dataset.nav;}
 text('workspace-title',workspaceRoutes[route]);if(focus){$('workspace-title').focus({preventScroll:true});window.scrollTo(0,0);}sync();
 }
 function setContext({available=false,business=false,label='',reset=false,allowed:routes=['business']}={}){ready=available;hasBusiness=business;allowed=new Set(['business',...routes]);text('workspace-context',label||'Selecciona tu negocio');show(reset?(ready?'home':'business'):route);}
 for(const b of shell.querySelectorAll('[data-nav],[data-go]'))b.addEventListener('click',()=>show(b.dataset.nav||b.dataset.go,true));
 setContext();return {setContext,sync,restore:()=>show(route)};
}
if(typeof module!=='undefined')module.exports={resolveWorkspaceRoute,routeVisible,workspaceRoutes};
