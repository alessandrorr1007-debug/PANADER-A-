# Fase 4.2 — Recetas y producción

Borrador SQL para PostgreSQL de pruebas, posterior a inventory.sql. No conectado todavía a Supabase ni al frontend.

- recipe_versions y recipe_items: recetas inmutables, versiones incrementales por nombre (sin distinguir mayúsculas), rendimiento base entero y entre 1 y 100 ingredientes únicos de la misma panadería. El nombre identifica la familia de receta; no existe renombrado de familia por ahora.
- production_batches y production_consumption: confirmación inmediata de producción por sucursal, unidades, autor, versión exacta de receta, cantidades, referencia al movimiento de inventario y costo de insumo capturado.
- Cantidad por ingrediente = cantidad base × unidades solicitadas / rendimiento base, redondeada hacia arriba al milésimo de la unidad base. Esta política evita redondear el consumo a cero, pero requiere validar con panaderos la precisión adecuada y el tratamiento de unidades indivisibles.
- Los propietarios/administradores crean versiones. Los operarios también pueden confirmar producción; consulta solo lee. RLS por empresa, FK compuestas y sin escrituras directas desde clientes.
- Cada lote y sus salidas se registran en una sola transacción, usando el mismo bloqueo por empresa que inventario. Si falta un insumo, se revierte todo. Reintentos con mismo UUID/payload/autor devuelven el lote existente; conflictos se rechazan. Crear versiones aún no tiene idempotencia de solicitud.
- Costo referencial total = suma de cantidad consumida × costo referencial vigente capturado; costo unitario = total / unidades producidas. No representa costo real contable; faltan mano de obra, energía, merma, costeo de compras y rendimiento real.
- Se permiten versiones históricas explícitas; no se ha implementado aprobación de recetas, planificación, anulación, stock de producto terminado ni ventas.
- CI ejecuta pruebas de versiones, rollback parcial, costos históricos, redondeo, reintentos, permisos y aislamiento. No sustituye pruebas de concurrencia ni Auth/Data API reales. Mantener bakery_private fuera de esquemas expuestos; ejecutar asesores y migraciones oficiales en entorno Supabase dedicado antes de producción.
