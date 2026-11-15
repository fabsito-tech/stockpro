# Hoja de seguimiento — STOCKPRO 1.0

## Etapa 1 — Estructura del proyecto y diseño principal
- **Estado:** Implementada en el repositorio; pruebas estáticas aprobadas. Sin publicar en GitHub Pages.
- **Funciones implementadas:** estructura HTML semántica, panel de muestra responsive para escritorio/móvil, navegación visual, menú móvil, paleta oscura con acento verde y datos marcados como ilustrativos.
- **Archivos creados:** `index.html`, `styles.css`, `app.js`, `README.md`, `SEGUIMIENTO.md`.
- **Pruebas realizadas:** presencia de etiquetas esenciales y viewport; selectores y enlaces internos; comprobación de sintaxis JS; ausencia de claves privadas; revisión de árbol responsivo y menú en móviles.
- **Errores encontrados:** la conexión Supabase marcada como conectada no ofrece una credencial utilizable en API en esta sesión.
- **Errores solucionados:** ninguno.
- **Pendiente:** validar el diseño en navegador real, establecer configuración Supabase segura y confirmar permisos; no hay autenticación, persistencia, productos, ventas ni publicación.
- **Próximo paso recomendado:** validar visualmente Etapa 1; luego Etapa 2 (panel administrativo real) solo con backend accesible y controles de seguridad previstos.

## Criterio para avanzar
No declarar terminadas funciones que no hayan sido ejecutadas y probadas. Nunca poner datos de demostración como datos reales. Activar RLS antes de exponer tablas y probar aislamiento entre tiendas.
