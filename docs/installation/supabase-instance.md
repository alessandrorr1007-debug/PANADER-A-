# Instancia dedicada de Supabase

- Proyecto: Panaderia-SaaS (dptzjteotamddcoogdvd), región sa-east-1.
- Estado verificado: ACTIVE_HEALTHY. Creación cotizada en USD 0/mes adicionales; no se contrataron servicios adicionales. El consumo y límites del plan deben supervisarse.
- Configuración web: frontend/config/public-config.js contiene únicamente URL y clave publicable.
- Migraciones registradas, en orden: tenant_foundation, onboarding, inventory, production, commerce, finance, subscriptions, accounts_billing.
- Verificación PostgreSQL: 27 tablas (20 públicas, 7 privadas), todas con RLS; 4 vistas. Sin permisos directos anon sobre tablas de aplicación, sin permisos directos authenticated sobre tablas privadas. Los siete avisos informativos de RLS sin políticas corresponden a tablas privadas intencionalmente cerradas. La lógica de funciones privadas debe quedar fuera de esquemas expuestos.
- GitHub Actions 46023444974 aprobó los tests previos. El escenario de cuentas, invitaciones, sesiones y cobros se ejecutó también contra la instancia real con claims de prueba y rollback; no se instalaron mocks de Auth ni quedaron cuentas, negocios, sesiones, invitaciones, precios, métodos ni pagos ficticios.
- Pendiente: comprobar en Dashboard Auth que confirmación de email es obligatoria, registro permitido y anónimos deshabilitados; configurar Site URL y redirect URLs al portal legítimo; revisar esquemas expuestos (no exponer bakery_private), SMTP y límites. Las comprobaciones SQL con claims simulados no equivalen a inicio de sesión HTTP, correo real o prueba E2E.
- Antes de uso real, registrar y confirmar la cuenta administrativa desde el portal con su propio correo; un operador autorizado debe añadir su UUID verificado a bakery_private.platform_admins. Nunca se autoconcede el rol. No hay administrador provisionado.
- Los precios y medios de pago permanecen deshabilitados hasta decisión explícita. No hay cobro automático, proveedor de pago, cuenta bancaria configurada, publicación web ni prueba de navegador real.
- No usar datos reales de clientes antes de la validación de autenticación, API, navegador, backups y revisión de permisos. No contratar servicios de pago sin autorización.

La migración adicional trial_once añade el registro privado de pruebas y la verificación de elegibilidad. No borrar su secreto ni el historial al eliminar usuarios. Consultar docs/modules/trial-once.md.
