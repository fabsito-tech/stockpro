# Aplicar migraciones de STOCKPRO con seguridad

**Estado actual:** `supabase/migrations/20261119222600_stockpro_core.sql` es una propuesta local, aún no aplicada ni probada en PostgreSQL/Supabase. No ejecutar contra producción hasta revisar el SQL, asegurar acceso de desarrollo y recibir autorización explícita.

## Qué hace y qué no hace esta migración

- Crea tipos, tablas, relaciones compuestas por `store_id`, índices, restricciones, triggers, vista de catálogo, funciones RPC, grants y políticas RLS.
- Asume un proyecto STOCKPRO nuevo y sin tablas propias. No contiene `DROP`, `TRUNCATE`, carga de usuarios, datos de prueba ni contraseñas.
- Aun así, agrega un esquema importante y un trigger en `auth.users`; no se ha ejecutado. Revisa cada sentencia antes de aprobarla.
- No completa el onboarding de una tienda ni invita usuarios automáticamente: el primer propietario debe iniciar sesión y llamar `create_store` desde un flujo autenticado.
- No hay flujo de devolución/anulación de venta implementado en este primer SQL; esos movimientos compensatorios quedan pendientes y no se debe borrar una venta.

## Flujo recomendado: validar primero local

1. Descargá/cloná el repositorio y trabajá en una rama de desarrollo. No guardes passwords, tokens ni claves en archivos del repo.
2. Instalá la Supabase CLI y Docker siguiendo las instrucciones oficiales de Supabase.
3. Si todavía no existe `supabase/config.toml`, inicializá el proyecto con `supabase init` y revisá el archivo generado antes de seguir; conservá las migraciones ya versionadas.
4. Levantá el stack local con `supabase start`.
5. Aplicá las migraciones únicamente al stack local con `supabase db reset` (este comando reinicia la base local; no lo ejecutes con `--remote`).
6. Ejecutá `supabase test db` para la suite pgTAP; luego ejecutá la prueba concurrente con `STOCKPRO_TEST_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres' bash supabase/tests/concurrency.sh`. El guion rechaza hosts no locales y limpia su fixture fijo.
7. Confirmá localmente todas las tablas, permisos, triggers, vista, funciones y pruebas descritas en `ARQUITECTURA.md`. Si algo falla, corregí el SQL y volvé a probar en local antes de tocar un proyecto alojado.

## Pruebas automatizadas en GitHub Actions

El workflow `.github/workflows/database-tests.yml` corre ante cambios relevantes y también se puede ejecutar manualmente desde GitHub Actions. En un runner Ubuntu instala Supabase CLI y `psql`, inicializa una configuración local, arranca un stack Supabase efímero y aplica las migraciones únicamente con `supabase db reset` sin `--remote`, `supabase link` ni inicio de sesión. Antes de resetear exige que la única migración SQL sea `20261119222600_stockpro_core.sql`.

Luego ejecuta la suite indicada por su ruta exacta con `psql` contra `127.0.0.1:54322`, cuenta aserciones TAP aprobadas/fallidas y corre `supabase/tests/concurrency.sh`, que también rechaza cualquier host no local. Sube logs sanitizados como artefactos por 14 días. El flujo no define secretos de Supabase ni una referencia de proyecto remoto. Revisar el resumen y los artefactos de GitHub Actions: crear el workflow no significa que las pruebas ya hayan corrido ni aprobado.

## Aplicación remota (requiere autorización explícita)

El proyecto STOCKPRO se observó como inactivo y el intento de consulta de tablas no pudo conectar. Antes de un despliegue, confirmá su estado en Supabase; no lo reactives sin revisar las condiciones y el costo que muestre Supabase.

Cuando el entorno esté autorizado y listo:

1. Confirmá el proyecto objetivo por su ref exacto (`aeymdbhejkkhratlgnfu`) y verificá que sea el entorno STOCKPRO de desarrollo, no otro proyecto.
2. Iniciá sesión en Supabase CLI con tu propia cuenta. Nunca pegues tokens o contraseñas en el chat ni los subas a GitHub.
3. En la raíz del repo, ejecutá primero una vista previa remota, sin aplicar:

   `supabase db push --dry-run --remote=aeymdbhejkkhratlgnfu`

4. Revisá el objetivo que muestra la CLI y la migración que planea aplicar. Detenete si muestra cualquier otra migración, seed o proyecto no esperado.
5. Antes de aplicar, hacé respaldo y verificá que el SQL y pruebas locales estén aprobados. Confirmá con el propietario la acción final.
6. Solo después de esa autorización, ejecutar explícitamente:

   `supabase db push --remote=aeymdbhejkkhratlgnfu`

   La CLI puede solicitar confirmación; no la omitas con `--yes` sin aprobación expresa. No ejecutar `db reset --remote`.
7. Verificá la migración registrada, inspeccioná las tablas/constraints/RLS y ejecutá pruebas con dos tiendas y usuarios de roles distintos. No usar todavía datos comerciales reales.

`db push --dry-run` es una vista previa de qué archivos pretende aplicar; no demuestra que SQL se ejecute correctamente ni que RLS sea segura. La prueba real debe hacerse primero en un entorno local o de desarrollo aislado.

## Fuentes oficiales

- [Deploy database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [Running commands against local and hosted projects](https://supabase.com/docs/guides/local-development/local-and-hosted-projects)
