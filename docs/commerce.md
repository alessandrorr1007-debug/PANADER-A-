# Fase 5.1 — Compras y ventas
Borrador PostgreSQL posterior a production.sql. No desplegado ni conectado a las interfaces.

- Proveedores por empresa, gestión por propietario/administrador.
- Recepciones de compras con uno o varios insumos, costo unitario documentado, entradas de inventario y total en PEN (suma de importes de línea redondeados a dos decimales). La recepción no implica pago ni modifica el costo referencial del catálogo.
- Inventario terminado derivado de unidades producidas menos unidades vendidas, por lote y sucursal. La vista finished_stock usa security_invoker para respetar RLS. No requiere backfill.
- Venta multilínea con lote explícito, unidades enteras, precio positivo de hasta dos decimales e importe calculado en servidor. Método declarado: efectivo, tarjeta, transferencia o billetera; no se procesa un pago real ni se emite comprobante fiscal.
- Operarios pueden registrar ventas; las compras requieren administrador/propietario. Todos los miembros leen datos comerciales de su negocio. Los precios son ingresados por el usuario autorizado; falta catálogo de precios y permisos específicos de caja.
- Transacciones atómicas, bloqueo compartido con inventario/producción, UUID de solicitud e igualdad del payload JSON (orden de líneas incluido), sin escritura directa de saldos o ventas. Si falla una línea, se revierte todo.
- No incluye devoluciones, vencimiento, mermas, transferencias de productos, FIFO automático, cierre de caja, cuentas por pagar, facturación SUNAT, impuestos ni costeo contable. El stock terminado es teórico hasta registrar mermas y devoluciones.
- Próximo paso: caja y control de precios, después integrar flujos al portal autenticado. Validar concurrencia con conexiones independientes y Supabase Auth/Data API en entorno dedicado. No instalar los mocks en un proyecto real.
