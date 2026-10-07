import Foundation

/// Representación unificada de un resultado de búsqueda de TMDb,
/// ya sea una película o una serie.
struct TMDbCandidate: Identifiable, Hashable {
    let id: Int
    let kind: MediaKind
    let title: String
    /// Título original (idioma de producción); sirve para reconocer coincidencias
    /// cuando el nombre del fichero está en inglés y TMDb devuelve el título localizado.
    let originalTitle: String?
    let year: Int?
    let overview: String
    let posterPath: String?

    var displayTitle: String {
        if let year { return "\(title) (\(year))" }
        return title
    }

    var posterURL: URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w92\($0)") }
    }
}

private func year(from date: String?) -> Int? {
    guard let date, date.count >= 4 else { return nil }
    return Int(date.prefix(4))
}

// Los DTOs se decodifican con `keyDecodingStrategy = .convertFromSnakeCase`.

struct TMDbMovieSearchResponse: Decodable {
    let results: [TMDbMovieResult]
}

struct TMDbMovieResult: Decodable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let releaseDate: String?
    let posterPath: String?

    var asCandidate: TMDbCandidate {
        TMDbCandidate(id: id, kind: .movie, title: title, originalTitle: originalTitle,
                      year: year(from: releaseDate), overview: overview ?? "", posterPath: posterPath)
    }
}

struct TMDbTVSearchResponse: Decodable {
    let results: [TMDbTVResult]
}

struct TMDbTVResult: Decodable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let firstAirDate: String?
    let posterPath: String?

    var asCandidate: TMDbCandidate {
        TMDbCandidate(id: id, kind: .episode, title: name, originalTitle: originalName,
                      year: year(from: firstAirDate), overview: overview ?? "", posterPath: posterPath)
    }
}

/// Temporada completa: una sola petición da el título de todos sus episodios.
struct TMDbSeasonResponse: Decodable {
    struct Episode: Decodable {
        let episodeNumber: Int
        let name: String
    }
    let episodes: [Episode]
}
