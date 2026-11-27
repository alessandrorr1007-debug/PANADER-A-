# Fase 3 — Fundación multiempresa

Estado: borrador SQL versionado, sin despliegue ni conexión del frontend.

## Modelo
- bakeries: empresa independiente.
- bakery_members: relación usuario/empresa; un usuario puede pertenecer a varias.
- branches: sucursal de una empresa, con clave compuesta disponible para futuras referencias.
- Roles propuestos: owner (propietario), admin (administrador), operator (operario), viewer (consulta).
- Todos los miembros leen su negocio y sus sucursales. Solo owner/admin crean y modifican sucursales (nombre y estado). No hay borrado desde clientes. La gestión de miembros y alta de negocios queda reservada al aprovisionamiento de confianza, todavía no implementado. Un operario/lector no puede cambiar su rol.

## Seguridad
Las tres tablas tienen RLS y permisos explícitos. Las políticas consultan la membresía real mediante auth.uid(); no confían en metadatos editables. El cliente no puede modificar bakery_id ni escribir membresías. No se expone ninguna función privilegiada. Los futuros módulos deberán incluir bakery_id y usar claves foráneas compuestas para impedir relaciones entre empresas. Antes de producción, decidir permisos por sucursal y flujos de invitaciones, auditoría, baja de miembros y alta transaccional de empresa/propietario.

## Validación
CI ejecuta las pruebas UI existentes y un PostgreSQL 16 desechable con un sustituto mínimo de auth.uid() para probar RLS y permisos. No reproduce Auth, JWT, Data API ni configuración completa de Supabase. Las pruebas cubren lectura, escritura permitida y denegada, cambio de empresa, escalada de rol, membresía múltiple y acceso anónimo. No se deben ejecutar fixtures en producción.

Para validar localmente en PostgreSQL vacío, con psql como administrador:
`psql -X -v ON_ERROR_STOP=1 -f tests/database/mock-auth.sql -f database/tenant-foundation.sql -f tests/database/tenant-isolation.sql`

El fichero database/tenant-foundation.sql es un borrador de diseño, no una migración oficial de Supabase. Cuando exista un entorno Supabase local dedicado: generar la migración mediante CLI, validar sobre base nueva, ejecutar pruebas de Auth y Data API y revisar Database Advisors. No instalar mock-auth.sql en Supabase.

Referencias: https://supabase.com/docs/guides/database/postgres/row-level-security y https://supabase.com/docs/guides/api/securing-your-api.

Siguiente: aprovisionamiento seguro, autenticación y conexión del frontend. Mantener la interfaz actual como demostración hasta validar el aislamiento real.
