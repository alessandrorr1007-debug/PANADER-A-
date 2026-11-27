'use strict';
const workspaceRoutes=Object.freeze({"home":"Resumen","inventory":"Almacén e insumos","production":"Recetas y producción","purchases":"Compras","sales":"Punto de venta","catalog":"Catálogo","orders":"Pedidos y clientes","cash":"Caja","reports":"Reportes","subscription":"Mi suscripción","business":"Mi negocio","team":"Trabajadores","account":"Mi cuenta"});
const operationalRoutes=['inventory','production','purchases','sales','catalog','orders','cash','reports'];
function resolveWorkspaceRoute(route,ready,hasBusiness){if(!Object.prototype.hasOwnProperty.call(workspaceRoutes,route))route='home';if(route==='business'||route==='account')return route;if(route==='subscription'||route==='team')return hasBusiness?route:'business';return ready?route:'business';}
function routeVisible(routes,route){return String(routes).split(/\s+/).includes(route);}
function workspacePermissions(role,grants=[],ready=false,hasBusiness=false){
 const routes=['business','account'];if(role==='owner'&&hasBusiness)routes.push('subscription','team');
 if(!ready||!hasBusiness)return routes;
 const has=(...keys)=>role==='owner'||keys.some(k=>grants.includes(k));
 routes.push('home');
 if(has('inventory'))routes.push('inventory');if(has('recipes','production'))routes.push('production');if(has('purchases'))routes.push('purchases');if(has('sales','prices'))routes.push('sales','catalog');if(has('sales'))routes.push('orders');if(has('cash'))routes.push('cash');if(has('reports'))routes.push('reports');
 return routes;
}
function createWorkspaceNavigation(){
 const $=id=>document.getElementById(id),shell=$('workspace-shell'),menu=$('workspace-menu-toggle');let ready=false,hasBusiness=false,route='business',role=null,allowed=new Set(['business','account']);
 const text=(id,value)=>{$(id).textContent=value;};
 function setMenu(open){shell.dataset.menuOpen=String(open);menu.setAttribute('aria-expanded',String(open));menu.setAttribute('aria-label',open?'Cerrar menú':'Abrir menú');}
 function sync(){
 for(const [target,content,source,permission] of [['overview-revenue','finance-content','fin-revenue','reports'],['overview-stock','inventory-content','inv-total','inventory'],['overview-alert','inventory-content','inv-low','inventory'],['overview-finished','commerce-content','com-stock','sales']]){
 const visible=ready&&allowed.has(permission);$(target).closest('[data-overview-route]').hidden=!visible;text(target,visible&&!$(content).hidden?$(source).textContent:'—');
 }
 const hasKpis=[...shell.querySelectorAll('[data-overview-route]')].some(el=>!el.hidden);$('overview-data-note').hidden=!hasKpis;$('overview-period').hidden=!allowed.has('reports');text('overview-period',ready&&allowed.has('reports')&&!$('finance-content').hidden?$('fin-range').textContent:'Reportes aún no disponibles.');
 $('subscription-empty').hidden=!$('own-subscription').hidden;
 const showChart=ready&&allowed.has('reports')&&!$('finance-content').hidden&&!document.body.classList.contains('role-demo');$('overview-sales-panel').hidden=!showChart;const overviewChart=$('overview-sales-chart');overviewChart.replaceChildren();if(showChart){text('overview-sales-period',$('fin-range').textContent);for(const child of $('fin-chart').children)overviewChart.append(child.cloneNode(true));}
 const hasOperations=operationalRoutes.some(key=>allowed.has(key));$('overview-no-modules').hidden=role!=='employee'||hasOperations;$('overview-links-title').hidden=role==='employee'&&!hasOperations;
 }
 function availableRoute(next){const resolved=resolveWorkspaceRoute(next,ready,hasBusiness);return allowed.has(resolved)?resolved:'business';}
 function show(next,focus=false){
 route=availableRoute(next);shell.dataset.activeRoute=route;
 for(const el of shell.querySelectorAll('[data-route-part]'))el.classList.toggle('route-off',!routeVisible(el.dataset.routePart,route));
 for(const b of shell.querySelectorAll('[data-nav],[data-go]')){const key=b.dataset.nav||b.dataset.go;const visible=allowed.has(key);b.hidden=!visible;b.disabled=!visible||availableRoute(key)!==key;if(b.dataset.nav){if(key===route)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');}}
 for(const label of shell.querySelectorAll('[data-nav-group]'))label.hidden=!label.dataset.navGroup.split(' ').some(key=>allowed.has(key));
 text('workspace-title',route==='business'&&role==='employee'?'Mi lugar de trabajo':workspaceRoutes[route]);if(focus){setMenu(false);$('workspace-title').focus({preventScroll:true});window.scrollTo(0,0);}sync();
 }
 function setContext({available=false,business=false,label='',reset=false,memberRole=null,grants=[]}={}){
 ready=available;hasBusiness=business;role=memberRole==='owner'?'owner':memberRole?'employee':null;allowed=new Set(workspacePermissions(memberRole,grants,ready,hasBusiness));shell.dataset.workspaceRole=role||'account';
 text('workspace-context',label||'Selecciona tu negocio');text('workspace-role',role==='owner'?'Administrador':role==='employee'?'Trabajador':'Mi cuenta');text('workspace-eyebrow',role==='owner'?'GESTIÓN DE TU PANADERÍA':role==='employee'?'ESPACIO DE TRABAJO':'MI ESPACIO');
 text('workspace-role-detail',role==='owner'?'Gestión del negocio':role==='employee'?'Acceso por permisos':'Selecciona un negocio');const count=operationalRoutes.filter(k=>allowed.has(k)).length;text('overview-access-count',role==='employee'?count+' módulos habilitados':'Operaciones del negocio');
 text('overview-eyebrow',role==='employee'?'MI JORNADA':'VISTA GENERAL');text('overview-title',role==='employee'?'Todo listo para tu jornada':'Tu negocio, bajo control.');text('overview-description',role==='employee'?'Accede a las herramientas que te asignó tu administrador.':'Consulta los indicadores de tu sucursal y entra directamente a cada operación.');
 const businessNav=shell.querySelector('[data-nav="business"] span');businessNav.textContent=role==='employee'?'Mi lugar de trabajo':'Mi negocio';if(reset)setMenu(false);show(reset?(ready?'home':'business'):route);
 }
 menu.addEventListener('click',()=>setMenu(menu.getAttribute('aria-expanded')!=='true'));shell.addEventListener('keydown',e=>{if(e.key==='Escape'&&menu.getAttribute('aria-expanded')==='true'){setMenu(false);menu.focus();}});
 for(const b of shell.querySelectorAll('[data-nav],[data-go]'))b.addEventListener('click',()=>show(b.dataset.nav||b.dataset.go,true));
 setMenu(false);setContext();return {setContext,sync,restore:()=>show(route)};
}
if(typeof module!=='undefined')module.exports={resolveWorkspaceRoute,routeVisible,workspaceRoutes,workspacePermissions};
