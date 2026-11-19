# STOCKPRO — Arquitectura y seguridad

Base técnica preparada a partir de la especificación de STOCKPRO enviada por Francisco el 19/11/2026. Este documento guía las migraciones; no afirma que las reglas estén ya implementadas o probadas.

## Alcance

STOCKPRO debe soportar varias tiendas sin que una tienda pueda consultar o alterar datos de otra. Las tablas comerciales privadas se vincularán a `store_id`; las identidades autenticadas se vincularán a `auth.users`. El frontend estático de GitHub Pages nunca contendrá secretos de servidor.

## Modelo previsto

- `stores`: nombre, logotipo, configuración y estado.
- `profiles`: datos de usuario vinculados a Supabase Auth; el perfil no controla roles.
- `store_members`: vínculo usuario-tienda y rol (`owner`, `admin`, `employee`).
- `categories` y `products`: catálogo privado por tienda; solo productos activos y publicados se exponen al catálogo público.
- `product_variants`: talle, color, SKU y existencia por variante.
- `sales` y `sale_items`: cabecera y detalle con precios fijados al momento de la operación.
- `stock_movements`: registro auditable de ingresos, egresos y ajustes.
- `customers`: contactos e historial limitado a la tienda que los registró.

Las tablas relacionadas con una tienda deben incluir claves foráneas compuestas que impidan asociar registros de una tienda a productos, variantes o ventas de otra. Usar restricciones `CHECK` para cantidades y precios no negativos, unicidad de SKU dentro de la tienda y claves de idempotencia para operaciones repetibles.

## Roles

- `owner`: administración de la tienda y sus miembros.
- `admin`: gestión comercial; no transfiere propiedad ni eleva roles.
- `employee`: consulta inventario y registra ventas, sin administrar miembros.
- `public`: únicamente lee los campos expresamente publicados del catálogo.

Los permisos se validan dentro de PostgreSQL; no se confía en `store_id`, `user_id` ni `role` enviados por el navegador. Las políticas serán específicas para `SELECT`, `INSERT`, `UPDATE` y `DELETE` en cada tabla expuesta.

## Aislamiento y RLS

1. Activar RLS para todas las tablas accesibles por la API.
2. Validar el usuario mediante `auth.uid()` y su membresía vigente en `store_members`.
3. Encerrar cada operación al `store_id` autorizado y al rol que corresponda.
4. Impedir la modificación propia de roles y limitar la gestión de membresías al `owner` mediante operaciones verificadas en la base.
5. Para el catálogo público, exponer solo campos públicos de productos publicados; no dar acceso a tablas privadas de clientes, costos, miembros, ventas o stock interno.
6. Evitar recursión/inyección en políticas: las funciones auxiliares de autorización, si hicieran falta, tendrán `search_path` fijo, permisos mínimos y pruebas dedicadas.

La clave `service_role` nunca va a HTML, JavaScript cliente, GitHub ni GitHub Pages. La clave publishable/anon solo se configura en el frontend una vez que las políticas estén instaladas y verificadas. No subir tokens, contraseñas ni secretos al repositorio.

## Ventas e inventario

El registro de venta debe realizarse con una sola función transaccional en PostgreSQL: validar membresía y rol, bloquear las variantes afectadas, comprobar existencia, insertar la venta y sus líneas, descontar stock y generar movimientos. Si falla cualquier validación, no se modifica nada. Una clave de idempotencia evita duplicar ventas por reintentos. Definir cancelaciones y devoluciones como movimientos compensatorios auditables, nunca como borrado silencioso.

## Pruebas obligatorias antes de publicar

Preparar dos tiendas de prueba A y B y usuarios de cada rol. Comprobar al menos:

- Owner A no lee ni modifica datos de B.
- Usuario no miembro no accede a datos privados.
- Employee no puede cambiar su rol ni gestionar miembros.
- Admin no transfiere propiedad ni eleva permisos.
- El catálogo sin sesión solo lista productos activos/publicados y sus campos públicos.
- Venta válida registra una vez y descuenta stock correctamente.
- Venta mayor al stock disponible se rechaza sin cambios parciales.
- Reintento idempotente no duplica la venta ni el movimiento.
- Ventas concurrentes no permiten stock negativo.

Guardar resultados de pruebas reproducibles; no declarar producción lista si falla una prueba.

## Publicación y operación

- Versionar SQL en migraciones revisables dentro de `supabase/migrations/`.
- Probar primero en un proyecto/entorno de desarrollo; no ejecutar cambios destructivos sobre datos reales.
- GitHub Pages aloja solo frontend estático, no secretos ni funciones servidor.
- Documentar variables públicas, configuración de Auth, respaldo, recuperación y transferencia por cliente.
- Revisar asesores de seguridad y probar el aislamiento completo antes de habilitar uso comercial.

## Decisión multi-tienda

La especificación permite proyectos independientes por comercio o una base multi-tenant con RLS. Para el prototipo actual se propone una base compartida con aislamiento obligatorio por `store_id`, porque el proyecto STOCKPRO activo está pensado como producto multi-tienda y la especificación exige aislamiento. Esta decisión no convierte el diseño en seguro por sí sola: no se activará uso real hasta que RLS y pruebas cruzadas estén implementadas. Se puede reconsiderar una instalación independiente por cliente si el modelo de entrega lo requiere.
