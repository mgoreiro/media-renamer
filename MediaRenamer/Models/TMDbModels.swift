import Foundation

/// Representación unificada de un resultado de búsqueda de TMDb,
/// ya sea una película o una serie.
struct TMDbCandidate: Identifiable, Hashable {
    let id: Int
    let kind: MediaKind
    let title: String
    let year: Int?
    let overview: String
    let posterPath: String?

    var displayTitle: String {
        if let year { return "\(title) (\(year))" }
        return title
    }
}

struct TMDbMovieSearchResponse: Decodable {
    let results: [TMDbMovieResult]
}

struct TMDbMovieResult: Decodable {
    let id: Int
    let title: String
    let overview: String?
    let releaseDate: String?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case releaseDate = "release_date"
        case posterPath = "poster_path"
    }

    var asCandidate: TMDbCandidate {
        let year = releaseDate?.prefix(4).isEmpty == false ? Int(releaseDate!.prefix(4)) : nil
        return TMDbCandidate(id: id, kind: .movie, title: title, year: year,
                              overview: overview ?? "", posterPath: posterPath)
    }
}

struct TMDbTVSearchResponse: Decodable {
    let results: [TMDbTVResult]
}

struct TMDbTVResult: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let firstAirDate: String?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
    }

    var asCandidate: TMDbCandidate {
        let year = firstAirDate?.prefix(4).isEmpty == false ? Int(firstAirDate!.prefix(4)) : nil
        return TMDbCandidate(id: id, kind: .episode, title: name, year: year,
                              overview: overview ?? "", posterPath: posterPath)
    }
}

struct TMDbEpisodeResponse: Decodable {
    let name: String
    let episodeNumber: Int
    let seasonNumber: Int

    enum CodingKeys: String, CodingKey {
        case name
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
    }
}
