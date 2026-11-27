# Acceso y alta inicial
El portal access.html es independiente de la demostración. config.js está vacío por defecto; sin URL y clave publicable válidas no se solicitan credenciales. No hay instancia real conectada.
- Usar solo URL HTTPS del proyecto supabase.co y clave sb_publishable_*. No colocar claves secretas o service_role.
- Configurar confirmación de correo obligatoria y desactivar usuarios anónimos. Configurar Site URL/redirects a access.html. Tras confirmar, iniciar sesión manualmente. No se implementa recuperación de contraseña todavía.
- El cliente utiliza Auth REST y Data API mediante fetch. La sesión permanece solo en memoria; se pierde al recargar y requiere volver a iniciar sesión al expirar. No se guardan tokens ni contraseñas localmente. El cierre intenta revocar la sesión remota.
- database/onboarding.sql es un borrador posterior a tenant-foundation.sql. La función privada privilegiada valida el usuario confirmado, serializa altas y crea negocio, propietario y sucursal de forma atómica. Solo se permite el alta inicial a quien no pertenece a ningún negocio; altas adicionales e invitaciones se implementarán después. El wrapper público es security invoker. Mantener bakery_private fuera de los esquemas expuestos.
- Antes de activar: generar migraciones oficiales en Supabase local, validar Auth y Data API, Database Advisors, políticas, concurrencia, configuración de correos, límites de alta, CSP y pruebas reales de navegador. No instalar los mocks en un proyecto real.
- La pantalla real solo lista negocios/sucursales; no conecta operaciones ficticias con clientes reales.
- Documentación: https://supabase.com/docs/guides/auth/passwords y https://supabase.com/docs/guides/api.
