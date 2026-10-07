import Foundation

enum MediaKind: String, Codable {
    case movie
    case episode
    case unknown
}

enum MatchStatus: Equatable {
    case pending          // aún no se ha buscado
    case searching        // búsqueda en curso
    case autoMatched      // coincidencia elegida (automática o manual), lista para renombrar
    case needsSelection   // varias coincidencias, el usuario debe elegir
    case noResults        // TMDb no devolvió nada
    case error(String)    // fallo de red / parseo
    case renamed          // ya renombrado en disco
    case renameFailed(String)

    /// Estados que "Buscar coincidencias" vuelve a intentar.
    var isSearchable: Bool {
        switch self {
        case .pending, .noResults, .error: return true
        default: return false
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
    @Published var episodeEnd: Int?
    @Published var kind: MediaKind

    // Resultado de la búsqueda en TMDb
    @Published var candidates: [TMDbCandidate] = []
    @Published var selectedCandidate: TMDbCandidate?
    @Published var episodeTitle: String?
    /// La coincidencia la eligió el usuario a mano: no se sobrescribe al propagar a la serie.
    var manuallySelected = false

    @Published var status: MatchStatus = .pending
    @Published var proposedFilename: String?
    /// Aviso no bloqueante (p. ej. no se pudo obtener el título del episodio).
    @Published var warning: String?

    /// Movimientos realizados en disco (vídeo + subtítulos); permiten deshacer.
    @Published var renamedOps: [RenameOp] = []

    init(url: URL, parsed: ParsedFilename) {
        self.originalURL = url
        self.parsedTitle = parsed.title
        self.parsedYear = parsed.year
        self.season = parsed.season
        self.episode = parsed.episode
        self.episodeEnd = parsed.episodeEnd
        self.kind = parsed.kind
    }

    var fileExtension: String {
        originalURL.pathExtension
    }

    /// Ubicación actual del fichero (tras renombrar, la nueva).
    var currentURL: URL {
        renamedOps.first?.to ?? originalURL
    }
}
