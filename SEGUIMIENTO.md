# Hoja de seguimiento — STOCKPRO 1.0

## Etapa 1 — Estructura del proyecto y diseño principal
- **Estado:** interfaz de muestra y estructura están en GitHub; no publicada en GitHub Pages.
- **Conectores:** repositorio `fabsito-tech/stockpro`; Supabase STOCKPRO ref `aeymdbhejkkhratlgnfu`, región `sa-east-1`. Estado consultado 19/11/2026: `INACTIVE`; la consulta de tablas no conectó. No se reactivó ni se modificaron datos remotos.
- **Pendiente:** validación visual/browser y conectar la aplicación una vez aprobada y probada la seguridad.

## Especificación de arquitectura
- **Estado:** documentada en `ARQUITECTURA.md`.
- **Pendiente:** aplicar y verificar en Supabase roles, aislamiento multi-tenant y operaciones.

## Esquema y pruebas SQL — trabajo preparado, remoto sin cambios
- **Estado:** propuesta versionada en GitHub; no ejecutada en ninguna base de datos, no se hizo `db push` ni cambio remoto.
- **Archivos:** `supabase/migrations/20261119222600_stockpro_core.sql`, `supabase/tests/20261119_stockpro_security.test.sql`, `supabase/tests/concurrency_seed.sql`, `supabase/tests/concurrency_cleanup.sql`, `supabase/tests/concurrency.sh`, `MIGRACIONES.md`.
- **Cambios del diseño:** tablas multi-tienda con FKs compuestas, índices/restricciones, RLS en las 10 tablas, RPC transaccional de ventas y ajuste de stock, clave idempotente; vistas explícitas para catálogo público y para ocultar costos de compra al rol employee. Las funciones `SECURITY DEFINER` fijan `search_path`; `EXECUTE` se revoca a `PUBLIC`/`anon` y se concede solo según uso esperado.
- **Pruebas automatizadas preparadas, aún no ejecutadas:** suite pgTAP con usuarios de dos tiendas y roles owner/admin/employee/no-miembro; consultas y cambios cruzados; grants/`SECURITY DEFINER`/`search_path`; catálogo anon; permisos por rol y campos de costo; ventas correctas, stock insuficiente, cantidades inválidas, reintento idempotente y conflicto de clave; falla inducida después de descontar una primera variante para verificar rollback total. Guion shell local crea stock de una unidad, fuerza transacciones solapadas con trigger de demora y comprueba exactamente una venta exitosa, stock cero y un movimiento.
- **Comprobaciones efectivamente ejecutadas en este turno:** `pglast` analizó sintácticamente 119 sentencias de migración, 107 sentencias del test pgTAP y 8/11 sentencias de seed/cleanup; `bash -n` aceptó el guion de concurrencia; validaciones estáticas confirmaron 10 declaraciones RLS, vistas sensibles, ausencia de instrucciones DROP/TRUNCATE y nombre de migración consistente. Son comprobaciones de archivos, no ejecución de SQL.
- **Errores/correcciones identificados en revisión estática:** se arregló el alias JSONB en la validación de items; se añadieron comprobaciones de entrada antes de agregar cantidades; se limitaron costos con vistas/column grants; se endureció `search_path`; se agregó prueba de error tardío con rollback. El análisis estático no descarta errores en runtime.
- **Pruebas pendientes:** ejecutar migración primero en un Supabase local descartable con `supabase db reset`; ejecutar `supabase test db`; correr `supabase/tests/concurrency.sh` con URL local. No se pudieron ejecutar: este entorno no tiene `psql`, Docker ni Supabase CLI y el proyecto remoto está inactivo. No se reactivó ni se usó remoto.
- **Riesgos/limitaciones pendientes de resolver antes de aceptar:** validar semántica y privilegios reales de las vistas (especialmente vistas PostgreSQL ejecutadas como owner), comportamiento de `auth.users` trigger en el Auth local, resultados completos de RLS y carreras concurrentes, y revisar migración en un stack limpio. El catálogo público intencionalmente usa una vista con filtro explícito; debe pasar las pruebas anon.
- **Próximo paso:** correr primero el ciclo local documentado en `MIGRACIONES.md`; revisar y corregir todos los resultados antes de pedir autorización para una prueba remota.
