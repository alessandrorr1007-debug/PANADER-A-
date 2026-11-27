# Acceso y alta inicial

Esta guía describe el estado actual del portal, no la demostración. Para un recorrido por los módulos consulta el [README principal](../../README.md).

## Probar el portal

Sirve la raíz del repositorio con `python -m http.server 8000` y abre http://localhost:8000/access.html. La demostración en index.html utiliza datos ficticios; admin.html es exclusivo de administradores de plataforma autorizados. La instancia dedicada Panaderia-SaaS ya está conectada en frontend/config/public-config.js mediante URL HTTPS y clave publicable; nunca usar claves secretas o service_role.

## Configuración previa al registro real

- En Supabase Auth habilitar correo y confirmación obligatoria, deshabilitar anónimos, revisar mínimo de contraseña, habilitar TOTP y configurar Site URL y redirecciones permitidas del portal legítimo.
- Configurar plantillas de confirmación y recuperación con el código de seis dígitos (`{{ .Token }}`), usando [confirmación](email-templates/confirmation.html) y [recuperación](email-templates/recovery.html).
- Revisar servicio SMTP y destinatarios autorizados; el correo por defecto tiene restricciones y no está validado para clientes públicos. No contratar un proveedor de pago sin autorización.
- Verificar que bakery_private permanezca fuera de los esquemas expuestos a la Data API.

## Flujo de usuario

Registrar correo y contraseña (mínimo 6 caracteres en interfaz y configuración de Auth), confirmar el código y después iniciar sesión. El segundo factor es opcional en cuentas normales y obligatorio para administradores de plataforma o usuarios con un factor verificado. La recuperación solicita un código de correo, el segundo factor si corresponde y la nueva contraseña; intenta cerrar todas las sesiones. No compartir secretos.

El alta inicial crea negocio, membresía de propietario y primera sucursal de forma atómica; otorga 14 días de prueba solo a un correo verificado e identidad elegibles. Los trabajadores invitados aceptan en Mi negocio usando su propio correo. No existe registro público ni alta automática de superadministrador: su cuenta se aprovisiona de forma privada desde el Dashboard de Supabase Auth y se autoriza mediante su UUID verificado.

La sesión está en memoria y no se persiste en el dispositivo. Una nueva sesión operativa sustituye la anterior. Recargar la página o expirar la sesión puede requerir autenticarse nuevamente.

## Validación pendiente

Antes de uso comercial: comprobar entrega real de correos, inicio y recuperación de sesión, MFA, autorización de superadministrador, permisos, concurrencia y navegación real en varios dispositivos; revisar límites, respaldos y políticas. No instalar mocks de Auth o datos de prueba en una instancia real. Consultar [instancia dedicada](supabase-instance.md) y [seguridad](../modules/auth-security.md).
