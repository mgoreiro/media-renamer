# Changelog

## 1.1 — 2026-10-07

### Correcciones
- Soltar muchos ficheros ya no provoca una condición de carrera (se perdían ficheros).
- Parser: las etiquetas de release se buscan como palabra completa (ya no se truncan «Webster», «Cambio», «España»…).
- Parser: títulos que son un año (`1917`, `2012`, `Blade Runner 2049`) se interpretan bien; `1920x1080` ya no se toma por un episodio; un año posterior al marcador de episodio se ignora.
- Cambiar solo mayúsculas/minúsculas (`foo.mkv` → `Foo.mkv`) funciona en APFS.
- El auto-match compara también con el título original, así que nombres en inglés casan con títulos localizados.
- Las series usan el año del nombre y, si no hay resultados con año, reintentan sin él (también las películas).
- Nombres de fichero: se sanean `\ * ? " < > |`, y se respetan el límite de 255 bytes y los puntos finales.
- Errores visibles: búsqueda manual con spinner, mensajes y estado «sin resultados»; aviso cuando no se obtiene el título de un episodio.
- Dejar de versionar `xcuserdata/`.

### Seguridad
- La API key se guarda en el **Llavero** (se migra automáticamente desde la versión anterior).
- Soporte del *API Read Access Token* v4 en cabecera `Authorization` (la key ya no viaja en la URL).

### Rendimiento y robustez
- Búsquedas en paralelo (4 simultáneas), cancelables, con barra de progreso.
- Una sola petición por temporada (con caché) en lugar de una por episodio.
- Reintentos con espera ante errores transitorios y límite de TMDb (429/5xx); timeouts de red.
- «Buscar coincidencias» reintenta los ficheros con error o sin resultados.
- La propagación a la serie respeta las elecciones manuales de otros episodios.
- Detección de colisiones de nombre dentro del lote antes de renombrar.

### Novedades
- **Deshacer renombrado** y rollback automático si falla una operación.
- Se renombran también los **subtítulos y ficheros asociados** (`srt ass ssa sub idx vtt sup nfo`).
- **Contexto de carpeta**: `Serie/Temporada 2/03.mkv` o `S01E03.mkv` dentro de la carpeta de la serie.
- Episodios múltiples (`S01E01E02`, `S01E01-E03` → `S01E01-E02`).
- Botón **Abrir…** (⌘O), quitar ficheros individuales, mostrar en el Finder, resumen y atajos de teclado.
- Carátulas en el selector de coincidencias; idioma de los títulos configurable.
- Ignora ficheros ocultos y paquetes al recorrer carpetas; más extensiones de vídeo.
- Accesibilidad (etiquetas VoiceOver) y atribución de TMDb.
- Pruebas automáticas (`Tests/run-tests.sh`, y `Tests/e2e/run-e2e.sh` con TMDb simulado) y script de empaquetado (`scripts/build-dmg.sh`).

## 1.0
Primera versión.
