# SaaS para panaderías

Proyecto independiente del sistema de panadería existente. Nombre provisional.

## Fase 1 — Prototipo UI/UX

Abrir `index.html` en un navegador o ejecutar `python -m http.server 8000` en la raíz y visitar http://localhost:8000. Sin dependencias ni credenciales.

- Menú adaptable a móviles, resumen, almacén, insumos, recetas, producción, ventas, compras, reportes y configuración.
- Dos negocios ficticios seleccionables; búsqueda en tablas y alertas de stock.
- Paleta verde neutra provisional. Datos exclusivamente ficticios. Ventas, compras y reportes son vistas iniciales, no módulos operativos.

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

- Tema claro y oscuro, con preferencia local y detección del tema del sistema.
- Iconos SVG, accesos rápidos, cabecera fija y navegación por fragmentos URL.
- Búsqueda insensible a tildes y mayúsculas, filtros por estado, contador de resultados y tablas desplazables.
- Ajustes responsive y de navegación por teclado.
- 19 comprobaciones de lógica y sintaxis validadas; repetir con Node.js: `node tests/ui.test.cjs`.
- Pendiente: pruebas en navegador real, revisión visual en dispositivos y validación con usuarios. No se implementó persistencia de datos ni seguridad multi-tenant. La preferencia de tema es lo único que se guarda localmente.
