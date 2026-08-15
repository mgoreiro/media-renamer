import Foundation

struct ParsedFilename {
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?
    var kind: MediaKind
}

/// Analiza el nombre de un fichero (sin ruta ni extensión) e intenta
/// extraer el título, el año y, si es un episodio, la temporada/episodio.
enum FilenameParser {

    // Palabras/etiquetas típicas de release que hay que eliminar del título.
    private static let junkTokens: [String] = [
        "1080p", "720p", "2160p", "480p", "4k", "uhd", "hdr", "hdr10",
        "web-dl", "webdl", "web", "webrip", "bluray", "blu-ray", "bdrip",
        "brrip", "dvdrip", "hdtv", "hdcam", "cam",
        "x264", "x265", "h264", "h265", "hevc", "avc",
        "aac", "ac3", "dts", "dd5.1", "5.1", "atmos",
        "amzn", "nf", "netflix", "hulu", "dsnp", "hmax",
        "dual", "multi", "subs", "subtitulado", "spanish", "castellano",
        "latino", "eng", "esp", "vose", "vosi", "remux", "proper", "repack",
        "extended", "unrated", "internal"
    ]

    static func parse(filename: String) -> ParsedFilename {
        let ext = (filename as NSString).pathExtension
        var name = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))

        // Normaliza separadores comunes a espacios para facilitar el análisis.
        let normalized = name.replacingOccurrences(of: ".", with: " ")
                              .replacingOccurrences(of: "_", with: " ")

        var season: Int?
        var episode: Int?
        var kind: MediaKind = .unknown
        var cutIndex: String.Index?

        // Patrón SxxEyy (p.ej. S01E02, s1e2)
        if let match = normalized.range(of: #"[Ss](\d{1,2})[ ]?[Ee](\d{1,3})"#, options: .regularExpression) {
            let matched = String(normalized[match])
            let digits = matched.uppercased()
                .replacingOccurrences(of: "S", with: " ")
                .replacingOccurrences(of: "E", with: " ")
                .split(separator: " ")
            if digits.count >= 2 {
                season = Int(digits[0])
                episode = Int(digits[1])
                kind = .episode
                cutIndex = match.lowerBound
            }
        }

        // Patrón 1x02
        if kind == .unknown, let match = normalized.range(of: #"(\d{1,2})[xX](\d{2,3})"#, options: .regularExpression) {
            let matched = String(normalized[match])
            let parts = matched.lowercased().split(separator: "x")
            if parts.count == 2 {
                season = Int(parts[0])
                episode = Int(parts[1])
                kind = .episode
                cutIndex = match.lowerBound
            }
        }

        // Patrón "Season 1 Episode 2"
        if kind == .unknown, let match = normalized.range(of: #"[Ss]eason[ ]?\d{1,2}.*?[Ee]pisode[ ]?\d{1,3}"#, options: .regularExpression) {
            let matched = String(normalized[match])
            if let seasonRange = matched.range(of: #"(?<=[Ss]eason[ ]?)\d{1,2}"#, options: .regularExpression) {
                season = Int(matched[seasonRange])
            }
            if let episodeRange = matched.range(of: #"(?<=[Ee]pisode[ ]?)\d{1,3}"#, options: .regularExpression) {
                episode = Int(matched[episodeRange])
            }
            kind = .episode
            cutIndex = match.lowerBound
        }

        name = normalized

        // Año de 4 dígitos (19xx / 20xx), típicamente entre paréntesis o suelto.
        var year: Int?
        if let match = name.range(of: #"\b(19\d{2}|20\d{2})\b"#, options: .regularExpression) {
            year = Int(name[match])
            // Si el año aparece antes del marcador de temporada/episodio, recorta ahí también.
            if let cut = cutIndex, match.lowerBound < cut {
                cutIndex = match.lowerBound
            } else if cutIndex == nil {
                cutIndex = match.lowerBound
            }
        }

        // El título es todo lo que precede al primer marcador (S01E01, año, o tag de calidad).
        var titlePart = name
        if let cutIndex {
            titlePart = String(name[name.startIndex..<cutIndex])
        } else {
            // Si no hay temporada/episodio ni año, corta en el primer tag de calidad conocido.
            let lower = name.lowercased()
            var earliestRange: Range<String.Index>?
            for token in junkTokens {
                if let r = lower.range(of: token) {
                    if earliestRange == nil || r.lowerBound < earliestRange!.lowerBound {
                        earliestRange = r
                    }
                }
            }
            if let earliestRange {
                let offset = lower.distance(from: lower.startIndex, to: earliestRange.lowerBound)
                let idx = name.index(name.startIndex, offsetBy: offset)
                titlePart = String(name[name.startIndex..<idx])
            }
        }

        let cleanTitle = cleanUpTitle(titlePart)

        if kind == .unknown {
            kind = .movie
        }

        return ParsedFilename(title: cleanTitle, year: year, season: season, episode: episode, kind: kind)
    }

    private static func cleanUpTitle(_ raw: String) -> String {
        var result = raw

        // Elimina paréntesis/corchetes con su contenido (a veces contienen el año, lo capturamos aparte).
        result = result.replacingOccurrences(of: #"[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: " ", options: .regularExpression)

        // Colapsa espacios múltiples y recorta.
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Quita guiones/puntos sueltos al final típicos de release names.
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-. "))

        return result
    }
}
