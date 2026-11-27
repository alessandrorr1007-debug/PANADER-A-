# Mapa del repositorio

Las tres páginas HTML permanecen en la raíz para conservar URLs y permitir hosting estático sin compilación.

| Ruta | Responsabilidad |
|---|---|
| index.html | Demostración con datos ficticios |
| access.html | Portal operativo autenticado |
| admin.html | Portal del administrador SaaS |
| frontend/auth/ | Controlador de acceso, selección de negocio y sesión |
| frontend/shared/api-client.js | Cliente REST y configuración validada |
| frontend/config/public-config.js | URL y clave publicable; nunca secretos |
| frontend/dashboard/ | Navegación y resumen |
| frontend/inventory/ | Insumos, existencias y movimientos |
| frontend/recipes-production/ | Recetas y lotes |
| frontend/commerce/ | Proveedores, compras, productos terminados y ventas |
| frontend/cash-reports/ | Caja, arqueo e indicadores |
| frontend/admin/ | Suscripciones y clientes de plataforma |
| frontend/demo/ | Lógica de demostración independiente |
| assets/styles/ | Estilos de demo y portal |
| backend/database/ | Borradores PostgreSQL (RLS, funciones y tablas) |
| tests/unit/ | Lógica de demo y navegación |
| tests/integration/ | Contratos HTTP simulados y estructura del repositorio |
| tests/database/ | Fixtures y pruebas de PostgreSQL aislado |
| docs/architecture/ | Diseño y arquitectura |
| docs/installation/ | Configuración de acceso |
| docs/modules/ | Documentación por dominio |
| .github/workflows/ | CI |

Las recetas y producción, compras y ventas, y caja y reportes comparten controladores existentes. No se crean carpetas vacías ni se duplican funcionalidades. Los scripts clásicos se cargan en orden desde las páginas; no se añade bundler. Los iconos SVG permanecen en las interfaces. La configuración sigue vacía por defecto. No hay despliegue real.

## Pruebas
Ejecutar desde la raíz con Node.js 22: `node --test tests/unit/*.test.cjs tests/integration/*.test.cjs`. GitHub Actions ejecuta además PostgreSQL 16 con fixtures. No utilizar fixtures en producción. El orden de aplicación de SQL está en el workflow.


**Acceso unificado:** `access.html` es el único formulario de acceso. El rol de plataforma se consulta al servidor después de autenticar, cumplir MFA y registrar la sesión. El panel de plataforma se monta en memoria solo para ese rol; no existe enlace público de administración. `admin.html` queda únicamente como redirección de compatibilidad. Las cuentas de plataforma se aprovisionan privadamente; las funciones de Supabase siguen verificando sus permisos.
