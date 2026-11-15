# Hoja de seguimiento — STOCKPRO 1.0

## Etapa 1 — Estructura del proyecto y diseño principal
- **Estado:** Implementada en el repositorio; pruebas estáticas aprobadas. Sin publicar en GitHub Pages.
- **Conectores / infraestructura:** Repositorio GitHub `fabsito-tech/stockpro` y proyecto Supabase `STOCKPRO` (`aeymdbhejkkhratlgnfu`, región `sa-east-1`) activos. El proyecto no tiene tablas todavía y el listado de `public` devolvió vacío. La organización gratuita existente y el proyecto inactivo previo quedaron intactos.
- **Funciones implementadas:** estructura HTML semántica, panel de muestra responsive para escritorio/móvil, navegación visual, menú móvil, paleta oscura con acento verde y datos marcados como ilustrativos.
- **Archivos creados:** `index.html`, `styles.css`, `app.js`, `README.md`, `SEGUIMIENTO.md`.
- **Pruebas realizadas:** presencia de etiquetas esenciales y viewport; selectores y enlaces internos; comprobación de sintaxis JS; ausencia de claves privadas; revisión de árbol responsivo y menú en móviles.
- **Errores encontrados:** la prueba de enlaces estáticos inicialmente asumió que todo destino de navegación tenía un ID HTML, pero los destinos son etapas aún no implementadas; se corrigió el criterio. El entorno no incluye Node ni navegador de pruebas, así que no se pudo validar JS en ejecución ni visualmente.
- **Errores solucionados:** se corrigió el criterio de validación; no se detectaron defectos de markup responsive en las comprobaciones estáticas.
- **Pendiente:** prueba visual en navegador real, configurar URL/clave publicable de Supabase sin secretos en GitHub y definir/validar esquema con RLS antes de datos reales; no hay autenticación, persistencia, productos, ventas ni publicación.
- **Próximo paso recomendado:** completar la prueba visual de Etapa 1; luego Etapa 2 con panel administrativo conectado y controles de seguridad previstos.

## Criterio para avanzar
No declarar terminadas funciones que no hayan sido ejecutadas y probadas. Nunca poner datos de demostración como datos reales. Activar RLS antes de exponer tablas y probar aislamiento entre tiendas.
