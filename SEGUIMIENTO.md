# Hoja de seguimiento — STOCKPRO 1.0

## Etapa 1 — Estructura del proyecto y diseño principal
- **Estado:** Interfaz y estructura publicadas en el repositorio; revisión estática inicial registrada. Sin publicar en GitHub Pages.
- **Conectores / infraestructura:** Repositorio GitHub `fabsito-tech/stockpro`. Proyecto Supabase STOCKPRO ref `aeymdbhejkkhratlgnfu`, región `sa-east-1`; había figurado activo al crearlo, pero el 19/11/2026 el estado consultado fue `INACTIVE` y falló la consulta a tablas. No reactivado ni modificado.
- **Funciones implementadas:** estructura HTML semántica, panel de muestra responsive para escritorio/móvil, navegación visual y datos marcados como ilustrativos.
- **Archivos de etapa:** `index.html`, `styles.css`, `app.js`, `README.md`, `SEGUIMIENTO.md`.
- **Pruebas realizadas:** comprobaciones estáticas de etiquetas, assets y media queries. No hubo navegador real ni entorno JS disponible entonces.
- **Pendiente:** prueba visual y de navegación en navegador; conexión al backend.

## Especificación de arquitectura (recibida 2026-11-19)
- **Estado:** documentada en `ARQUITECTURA.md`; no es implementación ni prueba RLS.
- **Pendiente:** aplicar y comprobar diseño de esquema, permisos, aislamiento multi-tenant y operaciones de stock.

## Primera implementación SQL — propuesta (2026-11-19)
- **Estado:** archivos preparados en el workspace local solamente. **No se ejecutaron en Supabase, no se subieron a GitHub y no se han probado contra un servidor PostgreSQL.** La conexión al proyecto Supabase fue imposible porque estaba inactivo.
- **Archivos:** `supabase/migrations/20261119222600_stockpro_core.sql` (tipos, tablas, claves foráneas compuestas, índices, restricciones, vista pública limitada, triggers, grants, RLS y RPC de tiendas, miembros, venta transaccional, idempotencia y ajuste de stock); `MIGRACIONES.md` (flujo de revisión y aplicación).
- **Pruebas realizadas localmente:** parser PostgreSQL `pglast` aceptó 115 sentencias; comprobación textual detectó ausencia de DROP/TRUNCATE, RLS declarado en las 10 tablas, RPC de venta y ajuste de stock, vista pública y límites de transacción. Estas verificaciones estáticas **no** prueban validez semántica en Supabase, grants efectivos, políticas, concurrencia ni aislamiento.
- **Errores encontrados/corregidos durante revisión:** se separaron grants por operación/columnas; se evitó que el rol `employee` pudiera ajustar stock por RPC; se añadió verificación de pertenencia producto-variante a línea de venta; se validan cantidades de entrada antes de agregarlas.
- **Pendiente antes de aplicación:** ejecutar primero contra Supabase local descartable y corregir errores; probar dos tiendas/roles, catálogo anon, seguridad de RPC, reintentos idempotentes, stock insuficiente, concurrencia y esquema RLS. Resolver qué hace falta para levantar/reconectar el proyecto remoto. No aplicar cambios remotos sin autorización explícita.
- **Importante:** el trabajo sigue siendo una propuesta; no declarar tablas ni políticas implementadas. Se observó un riesgo adicional que debe probarse y resolverse antes de aceptar el SQL: en una vista pública, comprobar que el owner y permisos de `public_catalog` realmente no permiten saltarse RLS ni exponer inventario privado.
