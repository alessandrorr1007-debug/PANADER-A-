# Fase 4 — Inventario e insumos

Borrador PostgreSQL para ejecutar después de onboarding.sql. No modifica el prototipo ni se ha aplicado a un servicio real.

## Modelo y reglas
- ingredients: catálogo por empresa, nombre único sin distinguir mayúsculas, unidad base kg/L/unit inmutable, costo referencial y estado activo.
- stock_balances: existencia y mínimo independientes por sucursal e insumo.
- stock_movements: historial de entradas y salidas, cantidad positiva, motivo, autor, fecha e identificador de solicitud. Sin edición ni borrado desde el cliente.
- Cantidades con hasta tres decimales; registrar siempre en unidad base. Conversiones g/ml y costeo promedio serán una fase posterior.
- Propietario y administrador gestionan catálogo y mínimos; operario puede registrar movimientos; consulta solo lee. Actualmente todos los miembros pueden leer todas las sucursales de su empresa.
- Las claves foráneas compuestas impiden combinar sucursales e insumos de empresas distintas. RLS limita las lecturas y la edición del catálogo.
- Saldo e historial se actualizan en una única transacción; bloqueo por empresa y fila evita descuentos simultáneos inconsistentes. El mismo identificador de solicitud y payload/autor devuelve el movimiento existente. Si cambian, se rechaza. Reintentos requieren una sucursal e insumo activos.
- No hay ventas, lotes, transferencias, vencimiento, producción ni valoración contable aún. Costo de catálogo no es costo real de movimientos.

## Verificación
Pruebas SQL de aislamiento, permisos, saldo, reintentos, precisión, stock negativo y escritura directa. CI utiliza PostgreSQL de prueba con auth simulado; todavía requiere validación Supabase real y pruebas concurrentes con conexiones independientes. Mantener bakery_private fuera de esquemas expuestos. El cliente deberá generar y conservar el UUID de solicitud durante reintentos. No usar los mocks en producción.

## Corrección de regresión
Se renombra la variable id en tests/database/onboarding.sql para evitar ambigüedad con una columna. No se cambia la función de alta inicial.
