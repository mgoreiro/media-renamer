import Foundation

/// Construye el nombre final de fichero (convención Plex/Jellyfin). Es puro
/// y no toca el disco, por lo que se puede probar de forma aislada.
enum FilenameBuilder {

    /// Máximo de bytes UTF-8 de un nombre de fichero en APFS/HFS+.
    static let maxFilenameBytes = 255

    static func build(kind: MediaKind,
                      title: String,
                      year: Int?,
                      season: Int?,
                      episode: Int?,
                      episodeEnd: Int? = nil,
                      episodeTitle: String?,
                      ext: String) -> String {
        let cleanTitle = sanitize(title)
        var base: String

        switch kind {
        case .movie, .unknown:
            base = cleanTitle + (year.map { " (\($0))" } ?? "")
        case .episode:
            var marker = String(format: "S%02dE%02d", season ?? 0, episode ?? 0)
            if let end = episodeEnd, let first = episode, end > first {
                marker += String(format: "-E%02d", end)
            }
            base = "\(cleanTitle) - \(marker)"
            if let episodeTitle, !episodeTitle.isEmpty {
                let t = sanitize(episodeTitle)
                if !t.isEmpty { base += " - \(t)" }
            }
        }

        let suffix = ext.isEmpty ? "" : ".\(ext)"
        return truncate(base, toFitWith: suffix) + suffix
    }

    /// Elimina o sustituye los caracteres problemáticos para nombres de fichero.
    static func sanitize(_ s: String) -> String {
        var result = s.replacingOccurrences(of: ":", with: " -")
        result = result.replacingOccurrences(of: "\"", with: "'")
        let replaceWithDash = CharacterSet(charactersIn: "/\\")
        let remove = CharacterSet(charactersIn: "*?<>|").union(.controlCharacters)
        result = String(result.unicodeScalars.compactMap { scalar -> Character? in
            if replaceWithDash.contains(scalar) { return "-" }
            if remove.contains(scalar) { return nil }
            return Character(scalar)
        })
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return result.isEmpty ? "Sin título" : result
    }

    private static func truncate(_ base: String, toFitWith suffix: String) -> String {
        let budget = maxFilenameBytes - suffix.utf8.count
        guard base.utf8.count > budget else { return base }
        var result = base
        while result.utf8.count > budget { result.removeLast() }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
    }
}
