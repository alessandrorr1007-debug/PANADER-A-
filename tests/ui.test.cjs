// Ejecutar desde la raíz: node tests/ui.test.cjs
const fs = require('node:fs');
const assert = require('node:assert/strict');
const html = fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const script = html.split('<script>')[1].split('</script>')[0];
new Function(script);
const results = new Function("const location={hash:''};"+script.split("$('nav').innerHTML=")[0]+`return [
['nueve módulos',validPages.length===9],['iconos completos',validPages.every(k=>paths[k])],
['ruta válida',route('warehouse')==='warehouse'],['ruta desconocida',route('unknown')==='dashboard'],
['búsqueda sin tildes',matches('Azúcar','azucar','low','low')],['filtro excluyente',!matches('Azúcar','azucar','low','ok')],
['búsqueda sin mayúsculas',matches('Harina','  HARINA ','ok','')],['sin coincidencias',!matches('Harina','sal','ok','')],
['total Aurora',chartSummary(samples.a)===6210],['total Trigal',chartSummary(samples.b)===3450],
['alertas Aurora',low(samples.a).length===3],['alertas Trigal',low(samples.b).length===1],
['inventario Aurora',stockRows(samples.a).length===4],['inventario Trigal',stockRows(samples.b).length===3],
['resumen Aurora',dashboard(samples.a).includes('Panadería Aurora')&&!dashboard(samples.a).includes('Panadería Trigal')],
['resumen Trigal',dashboard(samples.b).includes('Panadería Trigal')&&!dashboard(samples.b).includes('Panadería Aurora')],
['accesos rápidos',dashboard(samples.a).includes('quick-actions')],
['estado de stock',table(['Estado'],[[tag('Stock bajo',true)]]).includes('data-status="low"')],
['filtro de producción',filters('production').includes('value="planned"')]
]`)();
for (const [name, passed] of results) { assert.ok(passed,name); console.log('OK '+name); }
console.log(results.length+'/'+results.length+' comprobaciones aprobadas');

// Regresión visual de configuración: solo tema claro.
assert.match(html, /color-scheme:light/);
assert.doesNotMatch(html, /data-theme|prefers-color-scheme|panaderia-theme|id="theme"|applyTheme\(/);
assert.match(html, /--brand:#8B451F/);
assert.match(html, /--bg:#FAF6EF/);
assert.match(html, /--accent:#C58B43/);
console.log('5/5 comprobaciones de configuración de paleta aprobadas');

const visualChecks = new Function("const location={hash:''};"+script.split("$('nav').innerHTML=")[0]+`return [
['tarjetas de métricas con iconos',dashboard(samples.a).includes('metric-icon')],
['gráfico con escala',salesChart(samples.a).includes('chart-axis')],
['alertas con indicador',dashboard(samples.a).includes('stock-track')],
['métricas de almacén',inventoryMetrics(samples.a).includes('Disponibles')],
['métricas de recetas',recipeMetrics(samples.a).includes('200')],
['métricas de producción',productionMetrics(samples.a).includes('Planificados')],
['accesos con descripción',quick().includes('Existencias y movimientos')],
['ventas sin mezcla de clientes',!salesChart(samples.b).includes('1540')]
]`)();
for (const [name, passed] of visualChecks) { assert.ok(passed,name); console.log('OK '+name); }
console.log(visualChecks.length+'/'+visualChecks.length+' comprobaciones de componentes aprobadas');
