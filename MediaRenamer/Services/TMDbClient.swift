import Foundation

enum TMDbError: LocalizedError {
    case missingAPIKey
    case badResponse
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Falta la API key de TMDb. Configúrala en Ajustes."
        case .badResponse:
            return "TMDb devolvió una respuesta inesperada."
        case .decoding(let e):
            return "Error interpretando la respuesta de TMDb: \(e.localizedDescription)"
        case .network(let e):
            return "Error de red: \(e.localizedDescription)"
        }
    }
}

/// Cliente ligero para los endpoints de búsqueda de TMDb (v3, API key en query string).
struct TMDbClient {
    static let baseURL = URL(string: "https://api.themoviedb.org/3")!

    var apiKey: String

    private func makeURL(path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: TMDbClient.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)] + queryItems
        return components.url!
    }

    func searchMovie(title: String, year: Int?) async throws -> [TMDbCandidate] {
        guard !apiKey.isEmpty else { throw TMDbError.missingAPIKey }
        var items = [URLQueryItem(name: "query", value: normalizedQuery(title)), URLQueryItem(name: "language", value: "es-ES")]
        if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
        let url = makeURL(path: "search/movie", queryItems: items)
        let response: TMDbMovieSearchResponse = try await fetch(url)
        return response.results.map { $0.asCandidate }
    }

    func searchTV(title: String, year: Int?) async throws -> [TMDbCandidate] {
        guard !apiKey.isEmpty else { throw TMDbError.missingAPIKey }
        var items = [URLQueryItem(name: "query", value: normalizedQuery(title)), URLQueryItem(name: "language", value: "es-ES")]
        if let year { items.append(URLQueryItem(name: "first_air_date_year", value: String(year))) }
        let url = makeURL(path: "search/tv", queryItems: items)
        let response: TMDbTVSearchResponse = try await fetch(url)
        return response.results.map { $0.asCandidate }
    }

    /// Elimina tildes/diacríticos del título antes de enviarlo a TMDb, para que
    /// caracteres especiales (p.ej. "Cómo conocí a vuestra madre" -> "Como conoci
    /// a vuestra madre") no penalicen la búsqueda.
    private func normalizedQuery(_ title: String) -> String {
        title.folding(options: .diacriticInsensitive, locale: .current)
    }

    /// Obtiene el título de un episodio concreto de una serie ya identificada por su TMDb id.
    func episodeTitle(tvID: Int, season: Int, episode: Int) async throws -> String {
        guard !apiKey.isEmpty else { throw TMDbError.missingAPIKey }
        let url = makeURL(path: "tv/\(tvID)/season/\(season)/episode/\(episode)", queryItems: [URLQueryItem(name: "language", value: "es-ES")])
        let response: TMDbEpisodeResponse = try await fetch(url)
        return response.name
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TMDbError.badResponse
            }
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                throw TMDbError.decoding(error)
            }
        } catch let error as TMDbError {
            throw error
        } catch {
            throw TMDbError.network(error)
        }
    }
}
