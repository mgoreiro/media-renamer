# Revisión y mejoras

> **Estado tras la versión 1.1:** corregidos los puntos 1–12 de la sección 1, las secciones 2 (salvo notarización) y 3, y las mejoras 1, 2, 4, 5 (multi-episodio) y 6 de la sección 5, además de varias de las menores. Detalle en [CHANGELOG.md](../CHANGELOG.md).
> **Pendiente:** notarización con Developer ID, plantillas de nombre configurables, numeración absoluta/anime, localización con `Localizable.xcstrings`, migrar a `@Observable` (macOS 14+), pruebas de UI/XCTest en el proyecto, mover a carpetas `Serie/Temporada N/`, logo de TMDb.

Revisión inicial (v1.0):

Revisión estática de todo el código (no se ha compilado ni ejecutado la app). Ordenado por prioridad. Las referencias son `fichero:línea`.

## 1. Bugs y riesgos (prioridad alta)

| # | Problema | Dónde | Impacto / arreglo |
|---|---|---|---|
| 1 | **Data race** al soltar ficheros: `collected` se muta desde los callbacks de `loadObject`, que corren en hilos arbitrarios. | `DropZoneView.swift:36-51` | Pérdida de ficheros o crash intermitente al soltar muchos. Usar una cola serie/lock, o `async` con `TaskGroup`. |
| 2 | **Renombrar sólo cambiando mayúsculas falla**: en APFS (insensible a mayúsculas) `fileExists` devuelve `true` para el propio fichero. | `RenameEngine.swift:163` | `foo.mkv → Foo.mkv` da "Ya existe un fichero". Comparar con `resourceValues(fileIDKey)` o hacer el rename en dos pasos con nombre temporal. |
| 3 | **El parser corta títulos por subcadena**: los junk tokens se buscan con `range(of:)`, así que `web` corta "Webster", `cam` corta "Cambio", `eng` "Engaño", `esp` "España", `nf`, `multi`, `dual`… | `FilenameParser.swift:101-114` | Títulos truncados → búsquedas erróneas. Comparar por **palabra completa** (`\b…\b`). |
| 4 | **Títulos que son un año** (`1917`, `2012`, `Blade Runner 2049`, `1984`) se interpretan como año y dejan el título vacío. | `FilenameParser.swift:85-93` | Usar el **último** año válido (o el que va entre paréntesis) y no cortar si el título quedaría vacío. |
| 5 | **Falso positivo de episodio `NxMM`**: `1920x1080` casa con `(\d{1,2})[xX](\d{2,3})` (→ `20x108`). | `FilenameParser.swift:57` | Añadir `\b` / lookbehind `(?<!\d)`. |
| 6 | **Tokens con punto nunca coinciden**: `5.1` y `dd5.1` no pueden aparecer porque antes se reemplazó `.` por espacio. | `FilenameParser.swift:16-26,33` | Eliminar o tratarlos antes de normalizar. |
| 7 | **Auto-match falla con títulos localizados**: se pide `es-ES` y se compara sólo con `title`/`name` localizado. `The Matrix` ≠ `Matrix`, así que casi nunca hay match fuerte con nombres en inglés. | `RenameEngine.swift:33-38`, `TMDbModels.swift` | Decodificar `original_title` / `original_name` y comparar contra ambos. |
| 8 | **Series: se ignora el año parseado** (`searchTV(..., year: nil)`), perdiendo desambiguación (`Show (2019) S01E01`). | `RenameEngine.swift:21` | Pasar `item.parsedYear`. |
| 9 | **`sanitize` incompleto**: no cubre `\ * ? " < > |`, ni nombres que empiecen por `.`, ni el límite de 255 bytes. | `RenameEngine.swift:181` | Normalizar con un `CharacterSet` de ilegales y truncar. |
| 10 | **Errores silenciados**: la búsqueda manual traga la excepción (`results = []`), `isSearching` nunca se muestra, y si la búsqueda manual no da nada se muestran los candidatos antiguos como si fueran el resultado. | `MatchPickerSheet.swift:71-84,36` | Mostrar spinner y error; distinguir "sin resultados" de "no se ha buscado". |
| 11 | **Fallo del título de episodio ignorado**: si falla la red, `episodeTitle = nil` y el item queda `.autoMatched` con nombre sin título, indistinguible de un episodio sin título. | `RenameEngine.swift:117-119` | Marcar el item (aviso) o reintentar. |
| 12 | `xcuserdata/` está **versionado** pese a estar en `.gitignore` (se añadió antes). | `MediaRenamer.xcodeproj/xcuserdata/...` | `git rm -r --cached MediaRenamer.xcodeproj/xcuserdata` |

## 2. Seguridad y privacidad

- **API key en `UserDefaults` en claro** (`@AppStorage`). Mover al **Keychain**.
- La key viaja en la **query string**. TMDb admite el *API Read Access Token* (v4) en cabecera `Authorization: Bearer`, que evita que la key aparezca en logs, proxies o mensajes de error de red.
- **Sin sandbox** (justificado, ver README). Si algún día se distribuye: activar *Hardened Runtime*, firmar y notarizar. Para volver a sandbox habría que pedir al usuario la carpeta (`NSOpenPanel` + security-scoped bookmarks).
- `Info.plist`: `NSHumanReadableCopyright` vacío.

## 3. Rendimiento y robustez de red

- Búsquedas y obtención de títulos **totalmente secuenciales** (`searchAllGrouped`, `propagateToSeries`). Para una temporada de 24 episodios son 24 peticiones en serie. Paralelizar con `TaskGroup` limitado (~4-8 concurrentes) y cachear `(tvID, season)` con **un único** `GET /tv/{id}/season/{n}` en lugar de uno por episodio.
- Sin **reintentos ni manejo de 429** (TMDb limita ráfagas), sin timeout propio, sin **cancelación** (cerrar/limpiar durante una búsqueda deja tareas vivas).
- `URLSession.shared` e instanciar `RenameEngine`/`TMDbClient` por cada acceso a `engine` en `ContentView`; mejor inyectar un único cliente.
- Items en `.error` o `.noResults` **no se pueden reintentar** (`searchAllGrouped` sólo procesa `.pending`). Añadir "Reintentar".
- La propagación a la serie **sobrescribe** elecciones manuales previas de otros episodios y se ejecuta con el sheet ya mostrado sin indicador de progreso.

## 4. Arquitectura y calidad de código

- `MediaItem` + `LibraryModel` reenvían `objectWillChange` a mano con Combine. Con macOS 14+ se simplifica con `@Observable`; si se mantiene macOS 13, al menos cancelar la suscripción al borrar items.
- `MatchStatus.autoMatched` se usa también tras una selección manual; separar `.matched` (elegido) de la confianza (`auto`/`manual`).
- `RenameEngine` mezcla búsqueda, reglas de nombre y E/S de disco. Extraer `FilenameBuilder` (puro) y `FileRenamer` para poder testearlos.
- `TMDbMovieResult.asCandidate` usa `!` forzado; usar `Int(releaseDate.prefix(4))` con `flatMap`. Decoder con `.convertFromSnakeCase` elimina los `CodingKeys`.
- `.foregroundColor` / `.cornerRadius` están en desuso en versiones nuevas (`foregroundStyle`, `clipShape`).
- `posterPath` se decodifica pero **no se usa**: mostrar miniaturas en el selector.
- Cadenas en español hardcodeadas; `CFBundleDevelopmentRegion=es` sin catálogo. Migrar a `String(localized:)` + `Localizable.xcstrings`, y el `language=es-ES` de TMDb debería ser un ajuste.
- Sin **tests** ni CI. `FilenameParser` y `buildFilename` son funciones puras ideales para empezar (ver casos de la sección 1).

## 5. Funcionalidad / UX

Alta utilidad:
1. **Deshacer** (guardar mapa original→nuevo y revertir) y **vista previa/confirmación** antes de renombrar.
2. **Renombrar ficheros asociados**: subtítulos (`.srt`, `.ass`, `.sub`), `.nfo`, sidecars. Ahora sólo se aceptan vídeos y los `.srt` quedarían huérfanos.
3. **Plantilla de nombre configurable** (`{title} ({year})`, `S{season:02}E{episode:02}`…).
4. Usar el **contexto de carpeta** (`Serie/Temporada 1/03.mkv`) cuando el fichero no trae título.
5. **Episodios múltiples** (`S01E01E02`, `S01E01-E03`) y **numeración absoluta/anime**, especiales (temporada 0).
6. Detectar **colisiones de destino** entre items del mismo lote *antes* de renombrar.

Menores: botón/menú *Abrir…* además del drag & drop; quitar items individuales; ordenar/filtrar por estado; barra de progreso en búsqueda; opcionalmente mover a carpetas `Serie/Temporada N/`; accesibilidad (etiquetas VoiceOver en iconos de estado); ignorar ficheros ocultos y paquetes al recorrer carpetas (`.skipsHiddenFiles, .skipsPackageDescendants`); mostrar atribución/logo de TMDb exigida por sus términos.

## 6. Plan sugerido

1. **Quick wins** (≈1 sesión): #1, #3, #4, #5, #7, #8, #9, #12 + tests unitarios del parser.
2. **Robustez**: #2, #10, #11, reintentos/concurrencia, Keychain + Bearer token.
3. **Producto**: deshacer, preview, subtítulos asociados, plantillas.
