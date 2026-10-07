import Foundation

/// Contador de progreso compartido entre las tareas de búsqueda.
@MainActor
private final class ProgressCounter {
    let total: Int
    private(set) var done = 0
    private let report: ((Int, Int) -> Void)?

    init(total: Int, report: ((Int, Int) -> Void)?) {
        self.total = total
        self.report = report
        report?(0, total)
    }

    func advance(by n: Int) {
        done += n
        report?(done, total)
    }
}

@MainActor
final class RenameEngine {
    /// Búsquedas simultáneas máximas contra TMDb.
    private let maxConcurrentSearches = 4

    /// Cliente con los ajustes actuales (API key e idioma).
    var client: TMDbClient {
        TMDbClient(apiKey: AppSettings.shared.apiKey, language: AppSettings.shared.language)
    }

    // MARK: - Búsqueda

    /// Busca coincidencias en TMDb para un MediaItem y decide si hay un
    /// match automático claro o si el usuario debe elegir entre varias.
    func search(_ item: MediaItem) async {
        item.status = .searching
        item.warning = nil
        do {
            let client = self.client
            var candidates = try await lookup(client, item, usingYear: true)
            // Un año mal detectado (p. ej. "Blade Runner 2049") no debe impedir el resultado.
            if candidates.isEmpty, item.parsedYear != nil {
                candidates = try await lookup(client, item, usingYear: false)
            }
            item.candidates = candidates

            if candidates.isEmpty {
                item.status = .noResults
                return
            }

            // Auto-selección: un único resultado, o uno solo cuyo título (localizado u
            // original) y año coinciden con lo parseado.
            let wanted = normalize(item.parsedTitle)
            let strong = candidates.filter { candidate in
                let titleMatches = normalize(candidate.title) == wanted
                    || candidate.originalTitle.map { normalize($0) == wanted } == true
                let yearMatches = item.parsedYear == nil || candidate.year == nil || candidate.year == item.parsedYear
                return titleMatches && yearMatches
            }

            if candidates.count == 1 {
                await select(candidate: candidates[0], for: item)
            } else if strong.count == 1 {
                await select(candidate: strong[0], for: item)
            } else {
                item.status = .needsSelection
            }
        } catch is CancellationError {
            item.status = .pending
        } catch {
            item.status = .error(error.localizedDescription)
        }
    }

    private func lookup(_ client: TMDbClient, _ item: MediaItem, usingYear: Bool) async throws -> [TMDbCandidate] {
        let year = usingYear ? item.parsedYear : nil
        switch item.kind {
        case .movie, .unknown:
            return try await client.searchMovie(title: item.parsedTitle, year: year)
        case .episode:
            return try await client.searchTV(title: item.parsedTitle, year: year)
        }
    }

    /// Busca coincidencias para los items pendientes (o que fallaron antes), agrupando
    /// los episodios por serie para no repetir la misma búsqueda por cada episodio.
    /// Las búsquedas se ejecutan en paralelo (limitado) y se pueden cancelar.
    func searchAll(_ items: [MediaItem], onProgress: ((Int, Int) -> Void)? = nil) async {
        var seriesGroups: [String: [MediaItem]] = [:]
        var singles: [MediaItem] = []

        for item in items where item.status.isSearchable {
            if item.kind == .episode {
                let key = normalize(item.parsedTitle) + "|" + (item.parsedYear.map(String.init) ?? "")
                seriesGroups[key, default: []].append(item)
            } else {
                singles.append(item)
            }
        }

        let counter = ProgressCounter(total: singles.count + seriesGroups.values.reduce(0) { $0 + $1.count },
                                      report: onProgress)
        var units: [@MainActor () async -> Void] = []
        for movie in singles {
            units.append { [self] in
                await search(movie)
                counter.advance(by: 1)
            }
        }
        for group in seriesGroups.values {
            units.append { [self] in
                await searchSeries(group)
                counter.advance(by: group.count)
            }
        }

        await withTaskGroup(of: Void.self) { tasks in
            var iterator = units.makeIterator()
            for _ in 0..<maxConcurrentSearches {
                guard let unit = iterator.next() else { break }
                tasks.addTask { @MainActor in await unit() }
            }
            while await tasks.next() != nil {
                guard !Task.isCancelled, let unit = iterator.next() else { continue }
                tasks.addTask { @MainActor in await unit() }
            }
        }
    }

    /// Una búsqueda por serie; el resultado se reutiliza para todos sus episodios.
    private func searchSeries(_ group: [MediaItem]) async {
        guard let representative = group.first else { return }
        await search(representative)

        if representative.status == .autoMatched, let candidate = representative.selectedCandidate {
            for other in group.dropFirst() {
                if Task.isCancelled { break }
                await select(candidate: candidate, for: other)
            }
        } else {
            // Ambiguo, sin resultados o con error: comparten estado para poder resolverlo de una vez.
            for other in group.dropFirst() {
                other.candidates = representative.candidates
                other.status = representative.status
            }
        }
    }

    /// Cuando el usuario elige manualmente una coincidencia para un episodio,
    /// la aplica también al resto de episodios de la misma serie que aún no estén
    /// renombrados ni elegidos a mano.
    func propagateToSeries(from sourceItem: MediaItem, candidate: TMDbCandidate, in items: [MediaItem]) async {
        guard sourceItem.kind == .episode else { return }
        let key = normalize(sourceItem.parsedTitle)
        for item in items {
            guard item.id != sourceItem.id,
                  item.kind == .episode,
                  item.status != .renamed,
                  !item.manuallySelected,
                  normalize(item.parsedTitle) == key else { continue }
            await select(candidate: candidate, for: item)
        }
    }

    /// Fija la coincidencia de un item, obtiene el título del episodio y calcula el nombre propuesto.
    func select(candidate: TMDbCandidate, for item: MediaItem, manual: Bool = false) async {
        item.selectedCandidate = candidate
        item.manuallySelected = manual
        item.warning = nil
        item.episodeTitle = nil

        if item.kind == .episode, let season = item.season, let episode = item.episode {
            do {
                let titles = try await client.episodeTitles(tvID: candidate.id, season: season)
                if let title = titles[episode] {
                    item.episodeTitle = title
                } else {
                    item.warning = "TMDb no tiene título para S\(String(format: "%02d", season))E\(String(format: "%02d", episode))."
                }
            } catch is CancellationError {
                item.selectedCandidate = nil
                item.status = .pending
                return
            } catch {
                item.warning = "No se pudo obtener el título del episodio: \(error.localizedDescription)"
            }
        }

        item.proposedFilename = buildFilename(for: item)
        item.status = .autoMatched
    }

    // MARK: - Renombrado

    /// Nombre final según la convención Plex/Jellyfin, manteniendo el fichero en su carpeta.
    func buildFilename(for item: MediaItem) -> String {
        guard let candidate = item.selectedCandidate else {
            return item.originalURL.lastPathComponent
        }
        return FilenameBuilder.build(kind: item.kind, title: candidate.title, year: candidate.year,
                                     season: item.season, episode: item.episode, episodeEnd: item.episodeEnd,
                                     episodeTitle: item.episodeTitle, ext: item.fileExtension)
    }

    /// Renombra todos los items listos. Los que tendrían el mismo nombre de destino
    /// dentro del lote se marcan como error y no se tocan.
    func renameAll(_ items: [MediaItem]) {
        let ready = items.filter { $0.status == .autoMatched && $0.proposedFilename != nil }

        var byDestination: [String: [MediaItem]] = [:]
        for item in ready {
            let destination = item.originalURL.deletingLastPathComponent()
                .appendingPathComponent(item.proposedFilename!).path.lowercased()
            byDestination[destination, default: []].append(item)
        }

        for item in ready {
            let destination = item.originalURL.deletingLastPathComponent()
                .appendingPathComponent(item.proposedFilename!).path.lowercased()
            if (byDestination[destination]?.count ?? 0) > 1 {
                item.status = .renameFailed("Otro fichero del lote tendría el mismo nombre. Revisa la coincidencia.")
            } else {
                rename(item)
            }
        }
    }

    /// Renombra el fichero en disco (y sus subtítulos asociados) en su mismo directorio.
    func rename(_ item: MediaItem) {
        guard let proposed = item.proposedFilename else { return }
        let ops = FileRenamer.plan(source: item.originalURL, newName: proposed)

        if ops[0].from == ops[0].to {
            item.status = .renamed
            return
        }
        do {
            try FileRenamer.perform(ops)
            item.renamedOps = ops
            item.status = .renamed
        } catch {
            item.status = .renameFailed(error.localizedDescription)
        }
    }

    /// Revierte los renombrados realizados en esta sesión.
    func undoAll(_ items: [MediaItem]) {
        for item in items where item.status == .renamed && !item.renamedOps.isEmpty {
            do {
                try FileRenamer.perform(FileRenamer.reversed(item.renamedOps))
                item.renamedOps = []
                item.status = .autoMatched
            } catch {
                item.status = .renameFailed("No se pudo deshacer: \(error.localizedDescription)")
            }
        }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
         .trimmingCharacters(in: .whitespacesAndNewlines)
         .folding(options: .diacriticInsensitive, locale: .current)
    }
}
