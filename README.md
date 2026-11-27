# SaaS para panaderías

Proyecto independiente del sistema de panadería existente. Nombre provisional.

## Fase 1 — Prototipo UI/UX

Abrir `index.html` en un navegador o ejecutar `python -m http.server 8000` en la raíz y visitar http://localhost:8000. Sin dependencias ni credenciales.

- Menú adaptable a móviles, resumen, almacén, insumos, recetas, producción, ventas, compras, reportes y configuración.
- Dos negocios ficticios seleccionables; búsqueda en tablas y alertas de stock.
- Paleta cálida de panadería (crema, blanco, marrón tostado y dorado). Datos exclusivamente ficticios. Ventas, compras y reportes son vistas iniciales, no módulos operativos.

No hay autenticación, persistencia, pagos, despliegue ni aislamiento real de datos. La selección de negocio es únicamente visual.

## Hoja de ruta propuesta

1. Validar navegación y diseño con propietarios y trabajadores.
2. Definir unidades y conversiones, costos, rendimiento y merma, lotes y movimientos de inventario.
3. Implementar autenticación, negocios, membresías, sucursales y roles. Propuesta: PostgreSQL con políticas de seguridad por fila, aislamiento por negocio y pruebas de acceso cruzado.
4. Implementar insumos, recetas versionadas, compras y producción con transacciones atómicas, protección contra doble registro y validaciones de stock.
5. Implementar ventas, caja, reportes y auditoría.
6. Validar planes de suscripción, límites y facturación antes de comercializar.

Arquitectura objetivo propuesta: React + TypeScript, PostgreSQL, Supabase Auth y hosting estático. No hay servicios contratados.

## Validación inicial

Se verificó sintaxis JavaScript y siete comprobaciones de datos de ejemplo, alertas, separación visual y catálogo de navegación. Falta ejecutar pruebas de navegador, accesibilidad, móvil y seguridad multi-tenant. No se debe usar el prototipo con datos de clientes reales.

## Fase 2 — Refinamiento UI/UX

- Únicamente tema claro: se retiró el selector de tema, la detección del sistema y la persistencia de preferencias de tema.
- Iconos SVG, accesos rápidos, cabecera fija y navegación por fragmentos URL.
- Búsqueda insensible a tildes y mayúsculas, filtros por estado, contador de resultados y tablas desplazables.
- Ajustes responsive y de navegación por teclado.
- 19 comprobaciones de lógica y sintaxis validadas; repetir con Node.js: `node tests/ui.test.cjs`.
- Pendiente: pruebas en navegador real, revisión visual en dispositivos y validación con usuarios. No se implementó persistencia de datos ni seguridad multi-tenant. No se guardan preferencias de tema ni datos operativos localmente.

## Identidad visual

Tema claro obligatorio. Fondo crema `#FAF6EF`, superficies blancas `#FFFFFF`, texto cacao `#38271D`, botones marrón tostado `#8B451F`, acento dorado `#C58B43`. Alertas en ámbar con texto oscuro. Se comprobaron 8 pares de contraste de texto (mínimo 4.5:1) y 5 regresiones de configuración, además de las 19 pruebas existentes. Pendiente revisión visual en navegador.

## Refinamiento visual — dashboard y módulos

Tema exclusivamente claro y paleta de panadería conservada. Se rediseñaron navegación, cabecera, tarjetas KPI, acciones rápidas, gráfica con escala, alertas con barras de nivel, tablas, resúmenes de almacén/insumos/recetas/producción y estado vacío de compras. Ventas y reportes reutilizan la gráfica de ejemplo. No se añadieron operaciones reales ni dependencias externas. Se verificaron 32 comprobaciones de lógica, configuración y componentes generados mediante ejecución JavaScript; falta prueba visual y funcional en navegador real.

## Fase 3 — Fundación multiempresa

Se incorpora un borrador PostgreSQL con empresas, membresías, roles, sucursales y RLS, además de pruebas de aislamiento y un flujo de CI. El frontend sigue en demostración; sin despliegue ni conexión a Supabase. Ver [arquitectura](docs/tenant-architecture.md). Las pruebas de PostgreSQL quedan pendientes de ejecución en CI.

## Fase 3 — Acceso y alta inicial

Portal independiente con registro, inicio/cierre de sesión y selección de negocio/sucursal, preparado para Auth y Data API. Alta inicial transaccional definida en SQL. Configuración vacía por defecto, sin datos reales. Ver [acceso](docs/access.md). Las nuevas pruebas se ejecutarán en CI; falta integración real y revisión de seguridad en Supabase.

## Fase 4 — Inventario e insumos

Borrador SQL de catálogo, saldos por sucursal, movimientos atómicos, mínimos, RLS e idempotencia. Pruebas incorporadas a CI; se corrigió la ambigüedad de variable en el test de alta. El frontend continúa en demostración. Ver [inventario](docs/inventory.md).

## Fase 4.2 — Recetas y producción

Borrador SQL de recetas versionadas, rendimiento, lotes, consumo atómico y costos referenciales históricos. Pruebas incorporadas a CI. Ver [producción](docs/production.md). El frontend sigue en demostración.

## Fase 5.1 — Compras y ventas

Borrador SQL de proveedores, recepciones, reposición de materias primas, inventario terminado por lote y ventas multilínea. Pruebas integradas a CI. Ver [comercial](docs/commerce.md). Pendiente caja, precios, facturación e integración real.

## Fase 5.2 — Caja, precios y reportes

Borrador SQL de turnos, ingresos/egresos, arqueo, precios por versión y reportes diarios. Las nuevas ventas requieren caja abierta y precio configurado. Ver [finanzas](docs/finance.md). CI incorpora pruebas de permisos, totales, diferencias y reintentos; pendiente conexión real.

## Fase 6 — Modelo comercial SaaS

Borrador SQL de planes provisionales, prueba, vigencia, límites, acceso de consulta tras vencimiento y administración de clientes auditada. Sin cobros ni precios definidos. Ver [suscripciones](docs/subscriptions.md). Pendiente interfaz y validación real.

## Fase 7.1 — Integración de almacén e insumos

El portal autenticado consume las consultas y RPC de inventario; incluye registro de insumos, mínimos, movimientos y consultas por sucursal. Sin credenciales configuradas no realiza llamadas. Ver [integración](docs/inventory-integration.md). Pruebas HTTP simuladas en CI; falta conexión y validación E2E.

## Fase 7.2 — Integración de recetas y producción

Portal autenticado con catálogo versionado, editor de ingredientes, cálculo previo de cantidades y costo, confirmación de producción e historial. Ver [integración de producción](docs/production-integration.md). Sin conexión real configurada; pruebas en CI.

## Fase 7.3 — Integración comercial

Portal autenticado con proveedores, compras, existencias terminadas, precios, apertura/cierre básico de caja y ventas multilínea. Ver [integración comercial](docs/commerce-integration.md). No conectado a una instancia real; pruebas CI.

## Fase 7.4 — Caja y reportes

Portal autenticado con movimientos de efectivo, historial de arqueos, indicadores y ventas diarias (7/30/90 días). Se corrigió el validador de unidades de venta. Ver [finanzas](docs/finance-integration.md). CI pendiente; no conectado a una instancia real.

## Fase 7.5 — Panel SaaS

Portal separado admin.html para gestión de clientes y suscripciones, con autorización RPC, filtros, indicadores y edición manual. El cliente consulta su propio plan. Ver [administración SaaS](docs/admin-integration.md). Sin administrador real ni conexión configurada; pruebas CI.
