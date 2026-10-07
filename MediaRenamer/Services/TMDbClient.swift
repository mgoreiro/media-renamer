import Foundation

enum TMDbError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case notFound
    case badStatus(Int)
    case badResponse
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Falta la API key de TMDb. Configúrala en Ajustes."
        case .invalidAPIKey:
            return "TMDb rechazó la API key. Revísala en Ajustes."
        case .notFound:
            return "TMDb no encontró el recurso solicitado."
        case .badStatus(let code):
            return "TMDb devolvió un error (HTTP \(code))."
        case .badResponse:
            return "TMDb devolvió una respuesta inesperada."
        case .decoding(let e):
            return "Error interpretando la respuesta de TMDb: \(e.localizedDescription)"
        case .network(let e):
            return "Error de red: \(e.localizedDescription)"
        }
    }
}

/// Caché de títulos por temporada, compartida entre instancias del cliente.
actor TMDbSeasonCache {
    static let shared = TMDbSeasonCache()
    private var store: [String: [Int: String]] = [:]

    func titles(for key: String) -> [Int: String]? { store[key] }
    func save(_ titles: [Int: String], for key: String) { store[key] = titles }
}

/// Cliente ligero para los endpoints de TMDb v3. Acepta tanto la API key v3
/// (query string) como el "API Read Access Token" v4 (cabecera Bearer, preferible
/// porque la credencial no viaja en la URL).
struct TMDbClient {
    static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private static let maxRetries = 3
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    var apiKey: String
    var language: String = "es-ES"

    private var credential: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Los tokens v4 son JWT (largos y con puntos); las keys v3 son hex de 32 caracteres.
    private var usesBearer: Bool { credential.count > 60 && credential.contains(".") }

    // MARK: - Endpoints

    func searchMovie(title: String, year: Int?) async throws -> [TMDbCandidate] {
        var items = [URLQueryItem(name: "query", value: normalizedQuery(title)),
                     URLQueryItem(name: "language", value: language)]
        if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
        let response: TMDbMovieSearchResponse = try await fetch(path: "search/movie", queryItems: items)
        return response.results.map { $0.asCandidate }
    }

    func searchTV(title: String, year: Int?) async throws -> [TMDbCandidate] {
        var items = [URLQueryItem(name: "query", value: normalizedQuery(title)),
                     URLQueryItem(name: "language", value: language)]
        if let year { items.append(URLQueryItem(name: "first_air_date_year", value: String(year))) }
        let response: TMDbTVSearchResponse = try await fetch(path: "search/tv", queryItems: items)
        return response.results.map { $0.asCandidate }
    }

    /// Títulos de todos los episodios de una temporada (una petición, cacheada).
    func episodeTitles(tvID: Int, season: Int) async throws -> [Int: String] {
        let key = "\(language)|\(tvID)|\(season)"
        if let cached = await TMDbSeasonCache.shared.titles(for: key) { return cached }
        let response: TMDbSeasonResponse = try await fetch(
            path: "tv/\(tvID)/season/\(season)",
            queryItems: [URLQueryItem(name: "language", value: language)])
        let titles = Dictionary(response.episodes.map { ($0.episodeNumber, $0.name) },
                                uniquingKeysWith: { first, _ in first })
        await TMDbSeasonCache.shared.save(titles, for: key)
        return titles
    }

    /// Elimina diacríticos del título antes de enviarlo a TMDb para que caracteres
    /// especiales no penalicen la búsqueda.
    private func normalizedQuery(_ title: String) -> String {
        title.folding(options: .diacriticInsensitive, locale: .current)
    }

    // MARK: - HTTP

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard !credential.isEmpty else { throw TMDbError.missingAPIKey }
        var components = URLComponents(url: TMDbClient.baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = (usesBearer ? [] : [URLQueryItem(name: "api_key", value: credential)]) + queryItems
        var request = URLRequest(url: components.url!)
        if usesBearer { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetch<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        let request = try makeRequest(path: path, queryItems: queryItems)
        var attempt = 0

        while true {
            try Task.checkCancellation()
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await TMDbClient.session.data(for: request)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as URLError where attempt < TMDbClient.maxRetries && Self.isTransient(error) {
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoff(attempt: attempt, retryAfter: nil))
                continue
            } catch {
                throw TMDbError.network(error)
            }

            guard let http = response as? HTTPURLResponse else { throw TMDbError.badResponse }

            switch http.statusCode {
            case 200..<300:
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                do { return try decoder.decode(T.self, from: data) }
                catch { throw TMDbError.decoding(error) }
            case 401:
                throw TMDbError.invalidAPIKey
            case 404:
                throw TMDbError.notFound
            case 429, 500..<600:
                guard attempt < TMDbClient.maxRetries else { throw TMDbError.badStatus(http.statusCode) }
                attempt += 1
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                try await Task.sleep(nanoseconds: Self.backoff(attempt: attempt, retryAfter: retryAfter))
            default:
                throw TMDbError.badStatus(http.statusCode)
            }
        }
    }

    private static func isTransient(_ error: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost].contains(error.code)
    }

    private static func backoff(attempt: Int, retryAfter: Double?) -> UInt64 {
        let seconds = min(retryAfter ?? pow(2, Double(attempt - 1)), 10)
        return UInt64(seconds * 1_000_000_000)
    }
}
