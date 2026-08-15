import Foundation

@MainActor
final class RenameEngine {
    let client: TMDbClient

    init(apiKey: String) {
        self.client = TMDbClient(apiKey: apiKey)
    }

    /// Busca coincidencias en TMDb para un MediaItem y decide si hay un
    /// match automático claro o si el usuario debe elegir entre varias.
    func search(_ item: MediaItem) async {
        item.status = .searching
        do {
            let candidates: [TMDbCandidate]
            switch item.kind {
            case .movie, .unknown:
                candidates = try await client.searchMovie(title: item.parsedTitle, year: item.parsedYear)
            case .episode:
                candidates = try await client.searchTV(title: item.parsedTitle, year: nil)
            }

            item.candidates = candidates

            if candidates.isEmpty {
                item.status = .noResults
                return
            }

            // Auto-selección: si solo hay un resultado, o si uno coincide
            // exactamente en título (normalizado) y año, lo damos por bueno.
            let normalizedParsed = normalize(item.parsedTitle)
            let strongMatches = candidates.filter { candidate in
                let titleMatches = normalize(candidate.title) == normalizedParsed
                let yearMatches = item.parsedYear == nil || candidate.year == nil || candidate.year == item.parsedYear
                return titleMatches && yearMatches
            }

            if candidates.count == 1 {
                await select(candidate: candidates[0], for: item)
                item.status = .autoMatched
            } else if strongMatches.count == 1 {
                await select(candidate: strongMatches[0], for: item)
                item.status = .autoMatched
            } else {
                item.status = .needsSelection
            }
        } catch {
            item.status = .error(error.localizedDescription)
        }
    }

    /// Busca coincidencias para todos los items pendientes, agrupando los episodios
    /// por serie (según el título parseado) para no repetir la misma búsqueda en
    /// TMDb por cada episodio de una misma serie.
    func searchAllGrouped(_ items: [MediaItem]) async {
        var seriesGroups: [String: [MediaItem]] = [:]
        var others: [MediaItem] = []

        for item in items where item.status == .pending {
            if item.kind == .episode {
                let key = normalize(item.parsedTitle)
                seriesGroups[key, default: []].append(item)
            } else {
                others.append(item)
            }
        }

        for movie in others {
            await search(movie)
        }

        for (_, group) in seriesGroups {
            guard let representative = group.first else { continue }
            await search(representative)

            if representative.status == .autoMatched, let candidate = representative.selectedCandidate {
                // Coincidencia clara: se aplica a todos los episodios de la serie.
                for other in group.dropFirst() {
                    await select(candidate: candidate, for: other)
                }
            } else {
                // Ambiguo o sin resultados: comparte los mismos candidatos para que,
                // al resolver el primero manualmente, se pueda propagar al resto.
                for other in group.dropFirst() {
                    other.candidates = representative.candidates
                    other.status = representative.status
                }
            }
        }
    }

    /// Cuando el usuario elige manualmente una coincidencia para un episodio,
    /// la aplica también al resto de episodios detectados de la misma serie
    /// (mismo título parseado) que aún no estén renombrados.
    func propagateToSeries(from sourceItem: MediaItem, candidate: TMDbCandidate, in items: [MediaItem]) async {
        guard sourceItem.kind == .episode else { return }
        let key = normalize(sourceItem.parsedTitle)
        for item in items {
            guard item.id != sourceItem.id,
                  item.kind == .episode,
                  item.status != .renamed,
                  normalize(item.parsedTitle) == key else { continue }
            await select(candidate: candidate, for: item)
        }
    }

    /// El usuario elige manualmente una coincidencia de la lista.
    func select(candidate: TMDbCandidate, for item: MediaItem) async {
        item.selectedCandidate = candidate

        if item.kind == .episode, let season = item.season, let episode = item.episode {
            do {
                let title = try await client.episodeTitle(tvID: candidate.id, season: season, episode: episode)
                item.episodeTitle = title
            } catch {
                item.episodeTitle = nil
            }
        }

        item.proposedFilename = buildFilename(for: item)
        item.status = .autoMatched
    }

    /// Construye el nombre de fichero final siguiendo la convención Plex/Jellyfin,
    /// manteniendo el fichero en su carpeta original (sin mover/organizar en subcarpetas).
    func buildFilename(for item: MediaItem) -> String {
        let ext = item.fileExtension
        guard let candidate = item.selectedCandidate else {
            return item.originalURL.lastPathComponent
        }

        switch item.kind {
        case .movie, .unknown:
            let year = candidate.year.map { " (\($0))" } ?? ""
            return "\(sanitize(candidate.title))\(year).\(ext)"

        case .episode:
            let season = item.season ?? 0
            let episode = item.episode ?? 0
            let seasonEpisode = String(format: "S%02dE%02d", season, episode)
            if let epTitle = item.episodeTitle, !epTitle.isEmpty {
                return "\(sanitize(candidate.title)) - \(seasonEpisode) - \(sanitize(epTitle)).\(ext)"
            } else {
                return "\(sanitize(candidate.title)) - \(seasonEpisode).\(ext)"
            }
        }
    }

    /// Renombra el fichero en disco, en el mismo directorio, sin moverlo.
    func rename(_ item: MediaItem) {
        guard let proposed = item.proposedFilename else { return }
        let directory = item.originalURL.deletingLastPathComponent()
        let destination = directory.appendingPathComponent(proposed)

        guard destination != item.originalURL else {
            item.status = .renamed
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                throw NSError(domain: "MediaRenamer", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "Ya existe un fichero con ese nombre."])
            }
            try FileManager.default.moveItem(at: item.originalURL, to: destination)
            item.status = .renamed
        } catch {
            item.status = .renameFailed(error.localizedDescription)
        }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
         .trimmingCharacters(in: .whitespacesAndNewlines)
         .folding(options: .diacriticInsensitive, locale: .current)
    }

    /// Elimina caracteres problemáticos para nombres de fichero en macOS (":" y "/").
    private func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-")
         .replacingOccurrences(of: ":", with: " -")
    }
}
