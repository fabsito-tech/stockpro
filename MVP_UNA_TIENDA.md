# STOCKPRO — alcance del MVP para una sola tienda

## Cambio de alcance

Desde el 22/11/2026 el objetivo de producto es **un único negocio con un administrador**. Se dejan fuera multitienda, múltiples comercios, roles avanzados, suscripciones y funciones empresariales.

Para no borrar trabajo previo, `supabase/migrations/20261119222600_stockpro_core.sql`, la migración anterior y sus pruebas se conservan intactas como artefactos de la arquitectura anterior. Esa migración modela multi-tenancy y **no es el esquema objetivo para poner este MVP en producción**. No se ejecutó ningún cambio remoto por este cambio de alcance.

## Qué es la demo actual

El frontend reutiliza `index.html`, `styles.css` y `app.js`; ahora incluye gestión de productos y variantes (talle, color, unidades, precio), búsqueda, productos activos/archivados, carrito, validación de stock, confirmación de ventas con descuento de inventario, historial y catálogo público de productos activos. Persiste con `localStorage` del navegador y arranca con datos de ejemplo restaurables.

Es útil para presentar el flujo de una tienda, pero **no es una cuenta administrativa segura ni una base compartida**. Cualquier persona que abra el sitio público puede manipular la interfaz y solo verá/modificará los datos locales de su propio navegador. No hay sincronización entre dispositivos, respaldo de servidor, login, permisos, pagos ni facturación. El catálogo de Pages es una vista pública de la demo; no recibe cambios de otros navegadores.

## Antes de operar un comercio real

1. Reemplazar la propuesta multi-tenant actual por una migración nueva de un solo negocio, revisada y testeada localmente; no aplicar la antigua por inercia.
2. Habilitar Supabase Auth con una sola identidad administradora (alta inicial privada; nunca hardcodear usuario/clave).
3. Crear tablas para producto, variante/inventario, venta y líneas de venta. Protegerlas con RLS para que solo el administrador autenticado opere datos privados. El catálogo expone únicamente productos publicados y campos públicos.
4. Implementar venta como función transaccional del servidor: validar stock, guardar venta y descontar todas las variantes en una transacción; comprobar concurrencia e idempotencia en PostgreSQL local.
5. Configurar conexión de frontend con solo la clave pública/publishable y URL pública luego de aprobarlas; la `service_role`/secret key no va en frontend, Pages ni GitHub.
6. Probar auth, RLS, persistencia entre dispositivos, venta insuficiente/simultánea, respaldo/recuperación, catálogo desde una sesión separada y accesibilidad móvil. Recién después, con autorización explícita, aplicar la migración al proyecto remoto y cargar datos reales.

## Estado de pruebas

En el navegador publicado se comprobó la carga, alta de un producto, edición de nombre, adición de una segunda variante, ocultar un producto archivado del catálogo, carrito, venta, historial, descuento de 50 a 49 unidades, rechazo al intentar agregar más del stock disponible y persistencia al recargar. La interfaz tiene reglas adaptables, pero no se verificó en un celular real ni se probaron todos los escenarios. No se verificaron la restauración de demo, simultaneidad entre pestañas, backend ni seguridad. Las 70 pruebas de la migración multi-tenant anterior y su carrera se ejecutaron en Supabase local de GitHub Actions (documentadas en `SEGUIMIENTO.md`); no se borraron, pero no cubren esta demo localStorage ni autentican administradores.
