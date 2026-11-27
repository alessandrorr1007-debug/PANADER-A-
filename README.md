# Panadería SaaS

**Gestiona tu panadería desde un solo lugar.** Sistema web multiempresa para organizar insumos, recetas, producción, compras, ventas, caja y trabajadores. Cada negocio conserva su propia información y puede trabajar con varias sucursales según su plan.

[![Pruebas automatizadas](https://github.com/alessandrorr1007-debug/PANADER-A-/actions/workflows/verification.yml/badge.svg)](https://github.com/alessandrorr1007-debug/PANADER-A-/actions/workflows/verification.yml)
![Estado](https://img.shields.io/badge/estado-en_desarrollo-8B451F)
![Interfaz](https://img.shields.io/badge/tema-claro-C58B43)

> **Estado actual:** aplicación en desarrollo con base de datos dedicada en Supabase y módulos operativos implementados. Todavía no hay una URL pública de producción, ni un superadministrador activado. El envío de correos de confirmación y recuperación requiere configuración y validación real. No introducir datos de clientes reales hasta superar las pruebas de aceptación.

## Contenido

- [Cómo acceder](#1-cómo-acceder)
- [Primeros pasos](#2-primeros-pasos)
- [Guía de los módulos](#3-guía-de-los-módulos)
- [Ejemplo de una jornada](#4-ejemplo-de-una-jornada)
- [Trabajadores y permisos](#5-trabajadores-y-permisos)
- [Prueba gratuita y suscripciones](#6-prueba-gratuita-y-suscripciones)
- [Seguridad de tu cuenta](#7-seguridad-de-tu-cuenta)
- [Preguntas frecuentes](#8-preguntas-frecuentes)
- [Administración de la plataforma](#9-administración-de-la-plataforma)
- [Instalación, pruebas y desarrollo](#10-instalación-pruebas-y-desarrollo)
- [Próximas mejoras](#11-próximas-mejoras)

## 1. Cómo acceder

El repositorio tiene tres entradas independientes:

| Página | Para quién | Qué encontrarás |
|---|---|---|
| [index.html](index.html) | Personas que desean conocer el diseño | Demostración con datos ficticios, sin operaciones reales. |
| [access.html](access.html) | Administradores y empleados | Portal conectado a Supabase. Registro, inicio de sesión y operaciones de cada panadería. |
| [admin.html](admin.html) | Superadministrador autorizado | Gestión de suscripciones, clientes, precios de planes y revisión de pagos. |

Para probarlo en una computadora, consulta las instrucciones del apartado 10. Abrir estos archivos desde GitHub muestra su código; para utilizar la interfaz se necesita servirlos por HTTP/HTTPS. El portal público definitivo está pendiente de publicación.

## 2. Primeros pasos

### Crear tu cuenta

1. Abre el portal del negocio y selecciona **Crear cuenta**.
2. Escribe tu correo y una contraseña de al menos 12 caracteres.
3. Introduce el código de confirmación de seis dígitos recibido por correo.
4. Inicia sesión. Si tienes un segundo factor configurado, introduce el código de tu autenticador.
5. Si eres propietario y todavía no perteneces a un negocio, escribe el nombre de tu panadería y de tu primera sucursal.
6. Selecciona tu negocio y sucursal para empezar a gestionar las operaciones.

El correo debe estar verificado. La prueba gratuita comienza al crear tu primera panadería, no al instalar la web ni al iniciar sesión. Si ya utilizaste el beneficio, puedes registrar tu negocio sin una nueva prueba y contratar un plan cuando se habiliten los pagos.

**Si eres trabajador invitado:** registra y confirma el mismo correo que indicó tu administrador. En **Mi negocio**, acepta la invitación; no necesitas crear otra panadería.

### Orden recomendado de configuración

**Insumos → Proveedores y compras → Recetas → Producción → Precios → Caja → Ventas → Reportes.**

## 3. Guía de los módulos

La navegación está organizada en nueve espacios. Los formularios visibles dependen de tu rol, sucursal y vigencia de suscripción.

### Inicio

Consulta el resumen de los datos disponibles del negocio y accede a los módulos desde el menú. El selector permite trabajar en las sucursales activas a las que tienes acceso. El diseño es exclusivamente claro, con colores crema, blanco, marrón tostado y dorado.

### Almacén e insumos

Registra la materia prima (harina, azúcar, levadura, leche, etc.), su unidad base, costo inicial referencial y stock mínimo. El stock se controla por sucursal.

- **Entradas:** registra compras o movimientos manuales con cantidad, motivo, código de lote y vencimiento opcionales.
- **Salidas:** descuenta existencias sin permitir saldos negativos. La producción descuenta automáticamente los insumos.
- **Unidades:** puedes usar kg/g, L/ml o unidades. Por ejemplo, 500 g se guardan como 0,5 kg. No se convierten masa y volumen entre sí.
- **Stock mínimo:** define un umbral por insumo y sucursal para identificar faltantes.
- **Lotes:** consulta cantidad, fecha de vencimiento y estado. El stock total incluye lotes vencidos; el utilizable los excluye.
- **FEFO:** se consumen primero los lotes que vencen antes. Se bloquea una salida normal si no hay suficiente stock utilizable. Los lotes sin fecha se utilizan después de los lotes vigentes fechados.
- **Mermas:** el propietario o administrador puede seleccionar un lote, indicar cantidad y motivo (vencimiento, daño o desperdicio) y registrar su baja. Se conserva el movimiento.
- **Costos:** cada compra actualiza el costo promedio ponderado de las existencias del negocio. El historial muestra el precio de compra, costo anterior y nuevo promedio.

Las alertas se muestran dentro del almacén para los lotes vencidos y los que vencen en los próximos siete días. No hay notificaciones push. Introduce las fechas reales y retira materias primas no aptas; la aplicación no determina por sí sola su seguridad alimentaria.

### Compras y proveedores

1. Registra un proveedor.
2. Selecciónalo en **Recepción de compra**.
3. Añade los insumos, cantidades, costo por unidad base y datos de lote/vencimiento, si corresponde.
4. Revisa el importe total y confirma.

La recepción incrementa el inventario y crea los lotes de los insumos; también actualiza su costo promedio. Si ingresas gramos o mililitros, el precio sigue siendo por kg o L. Actualmente se admite un lote por insumo en cada recepción. Para varias partidas del mismo insumo, registra recepciones separadas.

Registrar una compra no ejecuta una transferencia de dinero ni un pago de proveedor. Las obligaciones pendientes y órdenes de compra son mejoras futuras.

### Recetas y producción

1. Crea una receta con su nombre, rendimiento esperado (cantidad de productos) e ingredientes.
2. Selecciona la cantidad que deseas producir.
3. Revisa las materias primas necesarias, stock utilizable y costo estimado.
4. Confirma el lote de producción.

El sistema escala las cantidades según el rendimiento, descuenta los lotes de insumos mediante FEFO y registra los productos terminados. Si falta stock utilizable, la operación se rechaza sin descontar parcialmente otros ingredientes.

Las recetas se guardan por versiones: usa el mismo nombre para registrar una nueva versión sin modificar la fórmula anterior. El costo de un lote producido se conserva aunque cambien los precios de los insumos. Actualmente se calcula costo referencial de materias primas, sin mano de obra, energía, alquiler, tributos ni rendimiento real diferente del planificado.

### Ventas

1. Configura el precio unitario para la versión de la receta que vendes.
2. Asegúrate de que la sucursal tenga un turno de caja abierto.
3. Selecciona los lotes de producto terminado y las unidades de venta.
4. Elige efectivo, tarjeta, transferencia o billetera digital.
5. Revisa y confirma la venta.

Se descuentan las existencias terminadas y se registra el importe. El sistema verifica stock y precio en el servidor. Los medios de pago son registros informativos: no se cobra al comprador desde la aplicación. Las devoluciones, descuentos, anulaciones y comprobantes tributarios aún no están implementados.

### Caja

El propietario o administrador puede abrir un turno con fondo inicial, registrar ingresos y egresos de efectivo con un motivo, consultar el efectivo esperado y cerrar el turno indicando el efectivo contado. El arqueo muestra la diferencia entre el importe esperado y el contado.

Las ventas en efectivo afectan el efectivo esperado; las digitales se registran por separado. Los pagos a proveedores no se descuentan automáticamente. Solo puede existir un turno abierto por sucursal.

### Reportes

Consulta indicadores de ventas, compras, unidades vendidas y margen estimado de materias primas, agrupados por día de Lima y por sucursal. Puedes revisar los últimos 7, 30 o 90 días.

**Importante:** el margen mostrado no es utilidad neta ni sustituye la contabilidad formal. La exportación a Excel/PDF y la facturación electrónica son funcionalidades pendientes.

### Mi negocio

Consulta tu cuenta, membresías, sucursales disponibles, invitaciones y sesiones. Los administradores titulares pueden invitar empleados y cambiar o retirar sus permisos. Se permite una sola sesión operativa por cuenta; al registrar una nueva, se invalida la anterior.

El alta inicial crea una sucursal. La base de datos tiene soporte y límites para varias sucursales, pero la gestión completa de altas, traslados y conciliaciones desde la interfaz todavía está pendiente.

### Mi suscripción

Consulta plan, estado, fecha de vencimiento y límites. Cuando el administrador de la plataforma habilite precios y métodos de pago, el propietario podrá comunicar un pago para revisión manual y consultar su historial.

## 4. Ejemplo de una jornada

Ejemplo ilustrativo, no datos de un cliente real:

| Operación | Resultado |
|---|---|
| Stock inicial de harina | 10 kg a S/ 2 por kg |
| Compra de harina | +5 kg a S/ 5 por kg |
| Nuevo stock y costo promedio | 15 kg a S/ 3 por kg |
| Receta de 100 panes | Utiliza 2 kg de harina y otros ingredientes |
| Producción de 100 panes | Descuenta 2 kg de harina utilizable; quedan 13 kg. Costo de harina: S/ 6. |
| Precio ilustrativo por pan | S/ 0,50 |
| Venta de 40 panes | S/ 20 de ventas; quedan 60 panes del lote. |

Para este ejemplo suponemos que la harina no está vencida, que hay stock de los demás ingredientes y que existe un turno abierto. El precio indicado no corresponde a un plan comercial del SaaS.

## 5. Trabajadores y permisos

El SaaS tiene **tres niveles de usuario**. Cada empleado tiene su propia cuenta; no comparte la contraseña del administrador y no compra otra suscripción.

| Nivel | Facultades |
|---|---|
| Superadministrador | Creador del SaaS: gestiona clientes, precios, pagos y suscripciones. No accede automáticamente a datos operativos de clientes. |
| Administrador | Titular del negocio que contrata la suscripción. Administra su panadería, sucursales, empleados, permisos y operaciones. |
| Empleado | Trabajador invitado por el administrador. Solo realiza operaciones autorizadas, dentro de su negocio y vigencia. No puede gestionar empleados, permisos ni pagos de suscripción. |

El administrador puede elegir permisos independientes al invitar a un empleado y modificarlos después de que acepte: almacén, recetas, producción, compras, ventas, precios, caja y reportes. Sin permisos, el empleado no puede operar ni ver datos operativos. El menú oculta módulos no autorizados; algunos datos compartidos son necesarios para módulos habilitados (por ejemplo, stock para producción y caja abierta para ventas). Los permisos son por panadería, no por sucursal todavía.

En **Mi negocio**, introduce el correo del empleado y selecciona permisos. El empleado registra y verifica su cuenta, y acepta la invitación. La invitación dura siete días y reserva un cupo. No hay correo de invitación automático; comparte la URL del portal. Retirar una membresía conserva su historial de operaciones.

## 6. Prueba gratuita y suscripciones

### Prueba única de 14 días

- Se concede una sola vez por correo verificado y por identidad de cuenta.
- El beneficio comienza al crear el primer negocio.
- Eliminar y recrear una cuenta con el mismo correo no otorga otros 14 días.
- Cambiar de navegador o dispositivo no reinicia el beneficio.
- Aceptar una invitación de trabajador no genera una prueba independiente.
- El registro privado de pruebas utiliza una huella protegida del correo. No evita todos los abusos mediante correos distintos.

### Planes provisionales

| Plan | Sucursales activas | Miembros totales |
|---|---:|---:|
| Inicial | 1 | 3 |
| Crecimiento | 3 | 10 |
| Empresa | 10 | 30 |

Los cupos incluyen al propietario. Los precios mensuales y anuales aún no están definidos ni habilitados para clientes.

### Pagar o renovar

Cuando estén habilitados los precios y medios de pago, el flujo será:

1. Elegir plan y periodicidad disponibles en **Mi suscripción**.
2. Realizar el abono por Yape, Plin o transferencia siguiendo las instrucciones publicadas.
3. Comunicar el importe y referencia de operación.
4. Esperar la revisión manual de la administración.
5. Tras la aprobación, consultar la nueva vigencia.

No existe cobro automático, pasarela de pagos ni validación bancaria automática. No hagas pagos mientras no haya instrucciones oficiales habilitadas. Al vencer la prueba o suscripción se bloquean nuevas operaciones; se conserva la consulta y el cierre de un turno de caja autorizado.

## 7. Seguridad de tu cuenta

- Confirma tu correo y usa una contraseña exclusiva de al menos 12 caracteres.
- Activa el segundo factor (TOTP) con una aplicación autenticadora compatible. El portal ofrece configuración manual de la clave y solicita el código temporal. Para superadministradores es obligatorio; una cuenta que ya lo activó también debe verificarlo.
- **Recuperar contraseña:** solicita un código desde «¿Olvidaste tu contraseña?», verifica el correo y el segundo factor si corresponde, establece una nueva contraseña y vuelve a iniciar sesión.
- Si pierdes el autenticador, necesitarás asistencia de un operador autorizado. No existe un flujo automático de recuperación de segundo factor ni códigos de respaldo.
- Una nueva sesión operativa reemplaza la anterior. El portal no almacena tokens de sesión de forma persistente; al recargar o expirar la sesión puede ser necesario ingresar de nuevo.
- Nunca compartas contraseñas, códigos ni secretos de autenticador.

Los datos se almacenan en PostgreSQL con políticas de seguridad por fila (RLS), permisos y comprobaciones de sesión. Cada negocio tiene su propio ámbito de acceso. Las pruebas automatizadas no garantizan por sí solas la seguridad de un despliegue público.

## 8. Preguntas frecuentes

**¿Puedo usarlo desde un celular?** La interfaz está diseñada para adaptarse a pantallas pequeñas, computadoras y tablets; falta completar la validación real en esos dispositivos.

**¿Por qué no puedo producir si aparece stock?** Puede haber lotes vencidos o cantidades insuficientes de stock utilizable. Revisa el almacén y los ingredientes de la receta.

**¿Qué ocurre si una operación parece no haberse guardado?** Actualiza el historial y verifica su resultado antes de repetir. Para movimientos con identificador de reintento, conserva los mismos datos durante la sesión. No repitas una compra o venta con un nuevo identificador sin revisar el historial.

**¿Puedo recuperar mi información al crear una cuenta nueva con el mismo correo?** No automáticamente. La recuperación de un negocio anterior requiere verificar la identidad y la propiedad con asistencia autorizada.

**¿El sistema emite boletas o facturas SUNAT?** No. Los registros son operativos internos. La facturación electrónica está pendiente.

**¿Funciona sin internet?** La demostración visual sí puede servirse localmente. El portal real necesita conexión a Supabase.

## 9. Administración de la plataforma

El panel separado de superadministración permite revisar clientes, planes, estados, vigencias, cupos y solicitudes de pago. También permite configurar precios, instrucciones de pago, aprobar o rechazar solicitudes y gestionar el estado de las suscripciones. El permiso se asigna en el servidor a una identidad verificada y requiere segundo factor. No hay credenciales administrativas públicas ni una cuenta real aprovisionada todavía.

## 10. Instalación, pruebas y desarrollo

### Ejecutar localmente

Requisitos: Git y Python 3. No se necesita instalar un framework ni dependencias de ejecución de JavaScript.

```bash
git clone https://github.com/alessandrorr1007-debug/PANADER-A-.git
cd PANADER-A-
python -m http.server 8000
```

| Vista | Dirección local |
|---|---|
| Demostración | http://localhost:8000/index.html |
| Portal del negocio | http://localhost:8000/access.html |
| Administración | http://localhost:8000/admin.html |

El servidor local sirve los archivos; no replica la base de datos. El portal utiliza una instancia Supabase dedicada ya configurada con URL y clave publicable. No usar credenciales secretas en JavaScript. Para probar sin afectar la instancia real, utiliza la demostración o una instancia de pruebas separada.

### Arquitectura

HTML, CSS y JavaScript modular en frontend; Supabase Auth y Data API; PostgreSQL con funciones transaccionales y RLS; GitHub Actions para pruebas Node y PostgreSQL. Los archivos SQL están en `backend/database/` y las pruebas en `tests/`. El mapa completo se encuentra en [organización del repositorio](docs/architecture/repository-layout.md).

### Estado técnico verificado

Al 27 de noviembre de 2026, la instancia dedicada tiene 12 migraciones instaladas y 32 tablas con RLS habilitado. Las pruebas de unidades, costos, lotes, vencimientos, FEFO y mermas pasaron en CI; el escenario de lotes se verificó además en PostgreSQL real mediante transacciones de prueba revertidas. Los resultados de la [última verificación funcional](https://github.com/alessandrorr1007-debug/PANADER-A-/actions/runs/46029076195) están disponibles en GitHub.

Pendiente de validar: registro por correo y recuperación reales, MFA desde navegador, configuración de SMTP, cuenta de superadministración, pruebas E2E, revisión visual, backups y publicación. No instalar los mocks de Auth ni los datos ficticios en Supabase real.

Presupuesto objetivo de desarrollo: **S/ 0**, sujeto a límites gratuitos y condiciones de cada proveedor. No se han contratado servicios adicionales.

### Documentación técnica

| Área | Documentación |
|---|---|
| Acceso y configuración | [Guía de acceso](docs/installation/access.md), [instancia Supabase](docs/installation/supabase-instance.md), [seguridad de cuentas](docs/modules/auth-security.md) |
| Multiempresa | [Arquitectura](docs/architecture/multi-tenant.md) |
| Almacén | [Inventario](docs/modules/inventory-integration.md), [unidades y costos](docs/modules/inventory-costs.md), [lotes y mermas](docs/modules/inventory-lots.md) |
| Recetas y producción | [Integración de producción](docs/modules/production-integration.md) |
| Comercio y finanzas | [Compras y ventas](docs/modules/commerce-integration.md), [caja y reportes](docs/modules/finance-integration.md) |
| Cuentas y suscripciones | [Cuentas y cobros](docs/modules/accounts-billing.md), [prueba única](docs/modules/trial-once.md) |
| Historial de desarrollo | [README histórico](docs/architecture/development-history.md) |

Los documentos técnicos históricos describen el estado de sus respectivas fases; si contradicen este README, consulta el estado actual del repositorio y las migraciones instaladas.

## 11. Próximas mejoras

| Prioridad | Pendiente |
|---|---|
| Crítica | Configurar correo, activar superadministrador y probar autenticación real. |
| Alta | Transferencias entre sucursales y conciliación de inventario físico. |
| Alta | Rendimiento real, valorización de mermas y costos completos de producción. |
| Alta | Catálogo, mejoras de punto de venta, devoluciones, pedidos y clientes. |
| Alta | Optimización de consultas, permisos por sucursal y rediseño de la interfaz. |
| Antes del lanzamiento | Política de privacidad, términos, respaldo, pruebas E2E y hosting gratuito. |

---

Panadería SaaS — proyecto independiente para la gestión de panaderías. La implementación está en desarrollo y no se presenta como un servicio comercial listo para producción.

Ver [tres niveles y permisos](docs/modules/employee-permissions.md) para el diseño de autorización y sus límites.

### Traslados y conteo físico

En el selector de sucursal, el administrador titular puede crear sucursales hasta el límite del plan. Desde Almacén, un usuario con permiso de inventario traslada insumos de la sucursal activa a otra, conservando lotes y fechas. También concilia el saldo de un lote con el conteo físico observado. Consulta los historiales. Un sobrante se registra en un nuevo lote con los mismos datos de origen; para un insumo sin lote registrado usa una entrada manual. No hay tránsito pendiente ni recepción separada. [Detalles](docs/modules/inventory-adjustments.md).

### Rendimiento real y costos de producción

Registra unidades planificadas, unidades realmente obtenidas y gastos declarados de mano de obra, energía y otros. El consumo se calcula con la cantidad planificada y el stock terminado con la real. El costo del lote queda registrado y se reparte entre unidades reales. Reportes incluyen margen de producción vendida, sin confundirlo con utilidad neta. [Detalles](docs/modules/production-costs.md).

### Catálogo, punto de venta y encargos

El catálogo asocia una ficha comercial (nombre, categoría, SKU y estado) a cada versión de receta y utiliza su precio configurado. El punto de venta incorpora buscador y tarjetas para añadir al carrito; los productos inactivos no se venden. Pedidos y clientes permite registrar clientes, encargos con fecha y líneas, confirmar, marcar listo, cancelar o entregar. Al entregar se comprueba stock/precio y se registra una única venta vinculada; requiere caja abierta. Los pedidos no reservan stock ni cobran adelantos. [Detalles](docs/modules/catalog-orders.md).
