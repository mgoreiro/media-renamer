import Foundation

struct ParsedFilename {
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?
    /// Último episodio de un fichero multi-episodio (S01E01E02, S01E01-E03).
    var episodeEnd: Int?
    var kind: MediaKind
}

/// Analiza el nombre de un fichero (sin ruta ni extensión) e intenta
/// extraer el título, el año y, si es un episodio, la temporada/episodio.
enum FilenameParser {

    // Etiquetas típicas de release. Se buscan siempre como palabra completa
    // (así "web" no corta "Webster" ni "cam" corta "Cambio").
    private static let junkTokens: [String] = [
        "1080p", "1080i", "720p", "2160p", "480p", "576p", "4k", "uhd", "hdr", "hdr10", "hdr10plus", "dv",
        "web-dl", "webdl", "webrip", "web", "bluray", "blu-ray", "bdrip", "bdremux", "brrip", "dvdrip", "hdtv",
        "hdrip", "hdcam", "cam", "x264", "x265", "h264", "h265", "hevc", "avc", "10bit", "8bit",
        "aac", "ac3", "eac3", "dts", "dts-hd", "truehd", "ddp5", "dd5", "dd2", "atmos",
        "amzn", "nf", "netflix", "hulu", "dsnp", "hmax", "atvp", "pcok",
        "dual", "multi", "subs", "subtitulado", "spanish", "castellano",
        "latino", "eng", "esp", "vose", "vosi", "remux", "proper", "repack",
        "extended", "unrated", "internal", "directors cut", "remastered"
    ]

    private static let junkRegex: NSRegularExpression = {
        let alternatives = junkTokens
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?<![A-Za-z0-9])(?:\(alternatives))(?![A-Za-z0-9])",
                                        options: [.caseInsensitive])
    }()

    private static let sxxEyy = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])[Ss](\d{1,2})[ ]?[Ee](\d{1,3})((?:[ ]?-?[ ]?[Ee]\d{1,3})*)(?!\d)"#)
    private static let nxmm = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])(\d{1,2})[xX](\d{2,3})(?!\d)"#)
    private static let longForm = try! NSRegularExpression(
        pattern: #"(?:[Ss]eason|[Tt]emporada)[ ]?(\d{1,2}).*?(?:[Ee]pisode|[Ee]pisodio|[Cc]ap[ií]tulo)[ ]?(\d{1,3})"#)
    private static let yearRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9])(19\d{2}|20\d{2})(?![0-9])"#)
    private static let seasonFolder = try! NSRegularExpression(
        pattern: #"^(?:season|temporada|temp|s)[ ._-]?(\d{1,2})$"#, options: [.caseInsensitive])
    private static let bareEpisode = try! NSRegularExpression(
        pattern: #"^(?:e|ep|episode|episodio|cap)?[ ]?(\d{1,3})$"#, options: [.caseInsensitive])

    // MARK: - API

    /// Analiza solo el nombre de fichero (la extensión se descarta).
    static func parse(filename: String) -> ParsedFilename {
        let ext = (filename as NSString).pathExtension
        let name = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        return parseName(name)
    }

    /// Analiza un fichero usando además las carpetas que lo contienen cuando el
    /// nombre no basta (`Serie/Temporada 1/03.mkv`, `Película (2019)/S01E03.mkv`…).
    static func parse(url: URL) -> ParsedFilename {
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        let grandparent = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent

        // "03.mkv" dentro de una carpeta de temporada.
        if let number = firstGroupInt(bareEpisode, in: base),
           let season = seasonNumber(inFolder: parent) {
            let show = parseName(grandparent)
            return ParsedFilename(title: show.title, year: show.year, season: season,
                                  episode: number, episodeEnd: nil, kind: .episode)
        }

        var parsed = parseName(base)
        guard parsed.title.isEmpty || isJunkOnly(parsed.title) else { return parsed }

        // Sin título en el nombre: se toma de la carpeta (saltando "Season N").
        if let season = seasonNumber(inFolder: parent) {
            let show = parseName(grandparent)
            parsed.title = show.title
            parsed.year = parsed.year ?? show.year
            parsed.season = parsed.season ?? season
        } else {
            let folder = parseName(parent)
            parsed.title = folder.title
            parsed.year = parsed.year ?? folder.year
            if parsed.season == nil, folder.kind == .episode { parsed.season = folder.season }
        }
        return parsed
    }

    // MARK: - Núcleo

    static func parseName(_ name: String) -> ParsedFilename {
        let text = name.replacingOccurrences(of: ".", with: " ")
                       .replacingOccurrences(of: "_", with: " ")
        let full = NSRange(text.startIndex..., in: text)

        var season: Int?
        var episode: Int?
        var episodeEnd: Int?
        var kind: MediaKind = .movie
        var episodeStart: String.Index?

        if let m = sxxEyy.firstMatch(in: text, range: full), let r = Range(m.range, in: text) {
            season = intGroup(m, 1, in: text)
            episode = intGroup(m, 2, in: text)
            if let extra = group(m, 3, in: text), !extra.isEmpty {
                let numbers = extra.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if let last = numbers.last, let first = episode, last > first { episodeEnd = last }
            }
            kind = .episode
            episodeStart = r.lowerBound
        } else if let m = nxmm.firstMatch(in: text, range: full), let r = Range(m.range, in: text) {
            season = intGroup(m, 1, in: text)
            episode = intGroup(m, 2, in: text)
            kind = .episode
            episodeStart = r.lowerBound
        } else if let m = longForm.firstMatch(in: text, range: full), let r = Range(m.range, in: text) {
            season = intGroup(m, 1, in: text)
            episode = intGroup(m, 2, in: text)
            kind = .episode
            episodeStart = r.lowerBound
        }

        // Año: se prefiere el que va entre paréntesis/corchetes y, si no, el último
        // que tenga un título delante (así "2012", "1917" o "Blade Runner 2049 (2017)" funcionan).
        var year: Int?
        var yearCut: String.Index?
        let maxYear = Calendar.current.component(.year, from: Date()) + 1
        var best: (year: Int, cut: String.Index, bracketed: Bool)?
        for m in yearRegex.matches(in: text, range: full) {
            guard let r = Range(m.range, in: text), let value = intGroup(m, 1, in: text), value <= maxYear else { continue }
            if let episodeStart, r.lowerBound > episodeStart { continue }
            var cut = r.lowerBound
            var bracketed = false
            if let open = previousNonSpace(before: r.lowerBound, in: text), "([".contains(text[open]) {
                cut = open
                bracketed = true
            }
            guard !cleanUpTitle(String(text[..<cut])).isEmpty else { continue }
            if let current = best, current.bracketed, !bracketed { continue }
            best = (value, cut, bracketed)
        }
        if let best { year = best.year; yearCut = best.cut }

        // Primera etiqueta de release con título delante.
        var junkCut: String.Index?
        for m in junkRegex.matches(in: text, range: full) {
            guard let r = Range(m.range, in: text) else { continue }
            if !cleanUpTitle(String(text[..<r.lowerBound])).isEmpty { junkCut = r.lowerBound; break }
        }

        let cut = [episodeStart, yearCut, junkCut].compactMap { $0 }.min() ?? text.endIndex
        let title = cleanUpTitle(String(text[..<cut]))

        return ParsedFilename(title: title, year: year, season: season, episode: episode,
                              episodeEnd: episodeEnd, kind: kind)
    }

    // MARK: - Helpers

    private static func cleanUpTitle(_ raw: String) -> String {
        var result = raw
        // Quita bloques entre paréntesis/corchetes/llaves.
        result = result.replacingOccurrences(of: #"[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Quita signos sueltos al principio/final (incluidos paréntesis sin cerrar).
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-. ([{").union(.whitespacesAndNewlines))
    }

    /// "1080p", "BluRay"…: un título que son solo etiquetas de release no es un título.
    private static func isJunkOnly(_ title: String) -> Bool {
        let range = NSRange(title.startIndex..., in: title)
        guard let m = junkRegex.firstMatch(in: title, range: range) else { return false }
        return m.range == range
    }

    private static func previousNonSpace(before index: String.Index, in text: String) -> String.Index? {
        var i = index
        while i > text.startIndex {
            i = text.index(before: i)
            if text[i] != " " { return i }
        }
        return nil
    }

    private static func seasonNumber(inFolder name: String) -> Int? {
        firstGroupInt(seasonFolder, in: name)
    }

    private static func firstGroupInt(_ regex: NSRegularExpression, in text: String) -> Int? {
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return intGroup(m, 1, in: text)
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: text) else { return nil }
        return String(text[r])
    }

    private static func intGroup(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> Int? {
        group(m, i, in: text).flatMap { Int($0) }
    }
}
