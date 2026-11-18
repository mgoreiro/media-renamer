# MediaRenamer

[Español](README.es.md)

A native macOS app (SwiftUI) that renames movies and TV episodes following the **Plex / Jellyfin** convention, using [TMDb](https://www.themoviedb.org/) to get the official title, the year and the title of every episode.

You drag in files or folders, the app reads the name, looks it up on TMDb, proposes a new name and, after you confirm, renames **in the same directory** (it does not move files or organise them into subfolders).

## What the result looks like

| Kind | Before | After |
|---|---|---|
| Movie | `The.Matrix.1999.1080p.BluRay.x264.mkv` | `The Matrix (1999).mkv` |
| Episode | `breaking.bad.s01e02.720p.hdtv.mkv` | `Breaking Bad - S01E02 - Cat's in the Bag....mkv` |

Titles are requested from TMDb in the configured language (Spanish, `es-ES`, by default). Associated subtitles (`.srt`, `.ass`…) are renamed along with the video.

## Install

Download the `.dmg` from [Releases](https://github.com/mgoreiro/media-renamer/releases), drag the app to *Applications* and, the first time, open it with right-click → *Open* (it is ad-hoc signed, without a Developer ID).

## Requirements

- macOS 13 or later (`LSMinimumSystemVersion`).
- Xcode to build it (project `MediaRenamer.xcodeproj`, no external dependencies).
- A free **v3** TMDb API key: <https://www.themoviedb.org/settings/api>.

## Usage

1. Open the project in Xcode and run it (⌘R).
2. Settings (⌘,) → paste your TMDb v3 API key or v4 token (it is stored in the Keychain) and choose a language.
3. Drag files or folders onto the drop zone, or use **Open…** (⌘O). Extensions: `mkv mp4 avi mov m4v wmv ts m2ts mpg mpeg flv webm`; folders are walked recursively (hidden files are skipped).
4. **Find matches** (⌘R; it can be cancelled, and failures are retried). Each row ends up in one of these states:
   - ✅ *autoMatched*: a single result, or only one with an exact title (and a compatible year). Ready to rename.
   - ❓ *needsSelection*: several matches; press **Choose…** and pick one (or search by hand).
   - ⚠️ *noResults* / *error*: no results or a network failure.
5. **Rename all** (⌘↩) renames only the items in the ✅ state (and their subtitles). They become 🔵 *renamed* and you can **Undo rename**. If two files in the batch would end up with the same name, none of them is renamed.

For series, choosing the match of one episode is **propagated** to the rest of the episodes of the same series (same parsed title).

In the manual search you can also **paste a TMDb link** (a movie or a series). The link takes priority over the kind detected from the file name, and the app warns you if the season or episode is missing.

### Names that need a little help

Besides the usual `S01E02` forms, the parser understands:

- **Disc rips:** files with no `SxxEyy` but with a disc marker and a `_Tnn` suffix (for example `Serie (1973) [DISC 1]…_T03.m4v`) are treated as episodes (season 1, or 0 for extras) instead of movies.
- **Running episode numbers:** `Cap 34` or `Capítulo 5`, with no season in the name, is treated as an absolute episode number. The title comes from the folder and, when you choose the series, the number is turned into a season and episode using the size of each season on TMDb.

## Architecture

```
MediaRenamer/
├── MediaRenamerApp.swift      Entry point: WindowGroup + Settings scene
├── ContentView.swift          Main screen, toolbar, selection sheet
├── Models/
│   ├── MediaItem.swift        ObservableObject per file + MediaKind / MatchStatus enums
│   ├── AppSettings.swift      API key (Keychain) and language
│   ├── LibraryModel.swift     Collection of MediaItem; forwards each item's objectWillChange
│   └── TMDbModels.swift       TMDbCandidate (unified model) + Decodable DTOs of the API
├── Services/
│   ├── FilenameParser.swift   Name (+ folders) → title / year / season / episode(s)
│   ├── FilenameBuilder.swift  Final Plex/Jellyfin name and sanitising (pure)
│   ├── FileRenamer.swift      Plan/execute/rollback of renames on disk + folder scanner
│   ├── KeychainStore.swift    Keychain access
│   ├── TMDbClient.swift       HTTP client (search/movie, search/tv, tv/{id}/season/{n}) with retries and cache
│   └── RenameEngine.swift     Orchestration: parallel search, auto-match, propagation, rename/undo
└── Views/
    ├── DropZoneView.swift     Drag & drop and folder expansion
    ├── FileRowView.swift      Row: original name, proposed name, status
    ├── MatchPickerSheet.swift Match picker + manual search
    └── SettingsView.swift     API key
```

### Data flow

```
Drop / Open… → MediaFileScanner.expand → LibraryModel.add
        └─ FilenameParser.parse(url:) → MediaItem(status: .pending)
Find → RenameEngine.searchAll   (≤4 in parallel, cancellable)
        ├─ movies: search() per file (retries without the year if there are no results)
        └─ series: 1 search per series, reused
              └─ select(candidate) → season titles (1 request, cached) → proposedFilename → .autoMatched
Rename → RenameEngine.renameAll → FileRenamer.plan (video + subtitles) → perform (with rollback)
Undo   → RenameEngine.undoAll   → FileRenamer.reversed
```

### FilenameParser

It normalises `.` and `_` and detects, in this order: `S01E02` (with multi-episode `S01E01E02` / `S01E01-E03`), `1x02` and `Season 1 Episode 2` / `Temporada 1 Episodio 2`. The preferred year is the one in parentheses or brackets or, failing that, the last one that has a title before it (and before the episode marker). The title is whatever comes before the first marker (episode, year or release tag as a whole word). If the name gives no title (`S01E03.mkv`, `03.mkv`), the folders are used (`Series/Season 2/03.mkv`).

### Auto-match

It is accepted automatically if TMDb returns 1 result, or if exactly 1 matches, by localised **or original** title (normalised without diacritics) and a compatible year. If there are no results with the year, it retries without it.

### Final name

- Movie: `Title (Year).ext`
- Episode: `Series - SxxEyy - Episode title.ext` (`SxxEyy-Ezz` for multi-episode; no title if TMDb does not return one, with a warning)
- Sanitising: `:` → ` -`, `/ \` → `-`, `"` → `'`, `* ? < > |` are removed, no trailing dots or spaces, 255 bytes at most.

## Design decisions worth knowing

- **No App Sandbox** (`MediaRenamer.entitlements`): renaming a dropped file requires writing to its parent folder, which the sandbox does not grant just because of the drag and drop. It does have `network.client` and the *Hardened Runtime*.
- **API key** in the Keychain; the v3 key (`api_key` query) or the v4 token (`Bearer` header, recommended) is accepted.
- All the UI text is in Spanish for now (no `Localizable.xcstrings` yet).

## Development

```bash
# Tests of the pure logic (parser, builder, renamer), without XCTest
Tests/run-tests.sh

# End-to-end test with a folder of series and a simulated TMDb (no network or Keychain)
Tests/e2e/run-e2e.sh

# Builds dist/MediaRenamer-<version>.dmg (universal arm64 + x86_64)
scripts/build-dmg.sh
```

Changes by version: [CHANGELOG.md](CHANGELOG.md).

## License

GPL-3.0, see [LICENSE](LICENSE).

This product uses the TMDb API but is not endorsed or certified by TMDb.

---

Quality review and improvements (state after 1.1): [docs/MEJORAS.md](docs/MEJORAS.md) (in Spanish).
