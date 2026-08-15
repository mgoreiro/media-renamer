import Foundation

enum MediaKind: String, Codable {
    case movie
    case episode
    case unknown
}

enum MatchStatus: Equatable {
    case pending          // aún no se ha buscado
    case searching        // búsqueda en curso
    case autoMatched      // coincidencia única de alta confianza
    case needsSelection   // varias coincidencias, el usuario debe elegir
    case noResults        // TMDb no devolvió nada
    case error(String)    // fallo de red / parseo
    case renamed          // ya renombrado en disco
    case renameFailed(String)

    static func == (lhs: MatchStatus, rhs: MatchStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.searching, .searching), (.autoMatched, .autoMatched),
             (.needsSelection, .needsSelection), (.noResults, .noResults), (.renamed, .renamed):
            return true
        case let (.error(a), .error(b)):
            return a == b
        case let (.renameFailed(a), .renameFailed(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Representa un fichero de vídeo que el usuario ha arrastrado a la app.
final class MediaItem: Identifiable, ObservableObject {
    let id = UUID()
    let originalURL: URL

    // Lo que hemos extraído del nombre de fichero original
    @Published var parsedTitle: String
    @Published var parsedYear: Int?
    @Published var season: Int?
    @Published var episode: Int?
    @Published var kind: MediaKind

    // Resultado de la búsqueda en TMDb
    @Published var candidates: [TMDbCandidate] = []
    @Published var selectedCandidate: TMDbCandidate?
    @Published var episodeTitle: String?

    @Published var status: MatchStatus = .pending
    @Published var proposedFilename: String?

    init(url: URL, parsed: ParsedFilename) {
        self.originalURL = url
        self.parsedTitle = parsed.title
        self.parsedYear = parsed.year
        self.season = parsed.season
        self.episode = parsed.episode
        self.kind = parsed.kind
    }

    var fileExtension: String {
        originalURL.pathExtension
    }
}
