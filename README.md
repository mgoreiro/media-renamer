# MediaRenamer

App nativa de macOS (SwiftUI) que renombra películas y episodios de series siguiendo la convención de **Plex / Jellyfin**, usando [TMDb](https://www.themoviedb.org/) para obtener el título oficial, el año y el título de cada episodio.

Arrastras ficheros o carpetas, la app interpreta el nombre, busca en TMDb, propone un nombre nuevo y, tras tu confirmación, renombra **en el mismo directorio** (no mueve ni organiza en subcarpetas).

## Resultado del renombrado

| Tipo | Antes | Después |
|---|---|---|
| Película | `The.Matrix.1999.1080p.BluRay.x264.mkv` | `The Matrix (1999).mkv` |
| Episodio | `breaking.bad.s01e02.720p.hdtv.mkv` | `Breaking Bad - S01E02 - Cat's in the Bag....mkv` |

Los títulos se piden a TMDb en el idioma configurado (por defecto español, `es-ES`). Los subtítulos asociados (`.srt`, `.ass`…) se renombran con el vídeo.

## Instalación

Descarga el `.dmg` desde [Releases](https://github.com/mgoreiro/media-renamer/releases), arrastra la app a *Aplicaciones* y, la primera vez, ábrela con clic derecho → *Abrir* (está firmada ad-hoc, sin Developer ID).

## Requisitos

- macOS 13 o superior (`LSMinimumSystemVersion`).
- Xcode para compilar (proyecto `MediaRenamer.xcodeproj`, sin dependencias externas).
- Una API key **v3** gratuita de TMDb: <https://www.themoviedb.org/settings/api>.

## Uso

1. Abre el proyecto en Xcode y ejecuta (⌘R).
2. Ajustes (⌘,) → pega tu API key v3 o tu token v4 de TMDb (se guarda en el Llavero) y elige idioma.
3. Arrastra ficheros o carpetas a la zona de drop, o usa **Abrir…** (⌘O). Extensiones: `mkv mp4 avi mov m4v wmv ts m2ts mpg mpeg flv webm`; las carpetas se recorren recursivamente (sin ocultos).
4. **Buscar coincidencias** (⌘R; se puede cancelar y se reintentan los fallos). Cada fila queda en uno de estos estados:
   - ✅ *autoMatched*: un único resultado, o uno solo con título exacto (y año compatible). Listo para renombrar.
   - ❓ *needsSelection*: varias coincidencias; pulsa **Elegir…** y selecciona (o busca a mano).
   - ⚠️ *noResults* / *error*: sin resultados o fallo de red.
5. **Renombrar todos** (⌘↩) renombra únicamente los items en estado ✅ (y sus subtítulos). Pasan a 🔵 *renamed* y se puede **Deshacer renombrado**. Si dos ficheros del lote acabarían con el mismo nombre, no se renombra ninguno de ellos.

Para series, elegir la coincidencia de un episodio se **propaga** al resto de episodios de la misma serie (mismo título parseado).

## Arquitectura

```
MediaRenamer/
├── MediaRenamerApp.swift      Punto de entrada: WindowGroup + escena Settings
├── ContentView.swift          Pantalla principal, toolbar, sheet de selección
├── Models/
│   ├── MediaItem.swift        ObservableObject por fichero + enums MediaKind / MatchStatus
│   ├── AppSettings.swift      API key (Llavero) e idioma
│   ├── LibraryModel.swift     Colección de MediaItem; reenvía objectWillChange de cada item
│   └── TMDbModels.swift       TMDbCandidate (modelo unificado) + DTOs Decodable de la API
├── Services/
│   ├── FilenameParser.swift   Nombre (+ carpetas) → título / año / temporada / episodio(s)
│   ├── FilenameBuilder.swift  Nombre final Plex/Jellyfin y saneado (puro)
│   ├── FileRenamer.swift      Plan/ejecución/rollback de renombrados en disco + escáner de carpetas
│   ├── KeychainStore.swift    Acceso al Llavero
│   ├── TMDbClient.swift       Cliente HTTP (search/movie, search/tv, tv/{id}/season/{n}) con reintentos y caché
│   └── RenameEngine.swift     Orquestación: búsqueda en paralelo, auto-match, propagación, renombrar/deshacer
└── Views/
    ├── DropZoneView.swift     Drag & drop y expansión de carpetas
    ├── FileRowView.swift      Fila: nombre original, propuesto, estado
    ├── MatchPickerSheet.swift Selector de coincidencia + búsqueda manual
    └── SettingsView.swift     API key
```

### Flujo de datos

```
Drop / Abrir… → MediaFileScanner.expand → LibraryModel.add
        └─ FilenameParser.parse(url:) → MediaItem(status: .pending)
Buscar → RenameEngine.searchAll   (≤4 en paralelo, cancelable)
        ├─ películas: search() por fichero (reintenta sin año si no hay resultados)
        └─ series: 1 búsqueda por serie y se reutiliza
              └─ select(candidate) → títulos de la temporada (1 petición, cacheada) → proposedFilename → .autoMatched
Renombrar → RenameEngine.renameAll → FileRenamer.plan (vídeo + subtítulos) → perform (con rollback)
Deshacer  → RenameEngine.undoAll   → FileRenamer.reversed
```

### FilenameParser

Normaliza `.` y `_` y detecta, por este orden: `S01E02` (con multi-episodio `S01E01E02`/`S01E01-E03`), `1x02` y `Season 1 Episode 2`/`Temporada 1 Episodio 2`. El año preferido es el que va entre paréntesis/corchetes o, si no, el último que tenga un título delante (y antes del marcador de episodio). El título es lo anterior al primer marcador (episodio, año o etiqueta de release como palabra completa). Si el nombre no da título (`S01E03.mkv`, `03.mkv`), se usan las carpetas (`Serie/Temporada 2/03.mkv`).

### Auto-match

Se acepta automáticamente si TMDb devuelve 1 resultado, o si exactamente 1 coincide —por título localizado **u original**, normalizados sin diacríticos— y año compatible. Si con año no hay resultados se reintenta sin año.

### Nombre final

- Película: `Título (Año).ext`
- Episodio: `Serie - SxxEyy - Título del episodio.ext` (`SxxEyy-Ezz` si es multi-episodio; sin título si TMDb no lo devuelve, con aviso)
- Saneado: `:` → ` -`, `/ \` → `-`, `"` → `'`, se eliminan `* ? < > |`, sin puntos/espacios finales y máx. 255 bytes.

## Decisiones de diseño a tener en cuenta

- **Sin App Sandbox** (`MediaRenamer.entitlements`): renombrar un fichero soltado requiere escribir en su carpeta padre, algo que el sandbox no concede sólo por el drag & drop. Sí tiene `network.client` y *Hardened Runtime*.
- **API key** en el Llavero; se acepta la v3 (query `api_key`) o el token v4 (cabecera `Bearer`, recomendado).
- Todo el texto de la UI está en español (sin `Localizable.xcstrings` todavía).

## Desarrollo

```bash
# Pruebas de la lógica pura (parser, builder, renombrador), sin XCTest
Tests/run-tests.sh

# Genera dist/MediaRenamer-<versión>.dmg (universal arm64 + x86_64)
scripts/build-dmg.sh
```

Cambios por versión: [CHANGELOG.md](CHANGELOG.md).

## Licencia

GPL-3.0 — ver [LICENSE](LICENSE).

Este producto usa la API de TMDb pero no está avalado ni certificado por TMDb.

---

Revisión de calidad y mejoras (estado tras la 1.1): [docs/MEJORAS.md](docs/MEJORAS.md).
