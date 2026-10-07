import Foundation

/// Un movimiento de fichero en disco (renombrado dentro del mismo directorio).
struct RenameOp: Equatable {
    let from: URL
    let to: URL
}

enum RenameError: LocalizedError {
    case destinationExists(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let name):
            return "Ya existe un fichero llamado «\(name)»."
        }
    }
}

/// Operaciones de disco: planificación (fichero + subtítulos asociados),
/// ejecución con rollback y deshacer.
enum FileRenamer {

    /// Ficheros acompañantes que se renombran junto al vídeo.
    static let sidecarExtensions: Set<String> = ["srt", "ass", "ssa", "sub", "idx", "vtt", "sup", "nfo"]

    /// Calcula todos los movimientos necesarios: el vídeo y los ficheros
    /// asociados (`Nombre.srt`, `Nombre.es.srt`…) que están a su lado.
    static func plan(source: URL, newName: String) -> [RenameOp] {
        let directory = source.deletingLastPathComponent()
        let destination = directory.appendingPathComponent(newName)
        var ops = [RenameOp(from: source, to: destination)]

        let oldBase = source.deletingPathExtension().lastPathComponent
        let newBase = destination.deletingPathExtension().lastPathComponent
        guard oldBase != newBase else { return ops }

        let siblings = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in siblings where url != source {
            guard sidecarExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            guard name == oldBase || name.hasPrefix(oldBase + ".") else { continue }
            let tail = name.dropFirst(oldBase.count)   // "" o ".es"
            let target = directory.appendingPathComponent("\(newBase)\(tail).\(url.pathExtension)")
            ops.append(RenameOp(from: url, to: target))
        }
        return ops
    }

    /// Ejecuta los movimientos; si uno falla, deshace los anteriores.
    static func perform(_ ops: [RenameOp]) throws {
        var done: [RenameOp] = []
        do {
            for op in ops {
                try move(op)
                done.append(op)
            }
        } catch {
            for op in done.reversed() { try? move(RenameOp(from: op.to, to: op.from)) }
            throw error
        }
    }

    static func reversed(_ ops: [RenameOp]) -> [RenameOp] {
        ops.reversed().map { RenameOp(from: $0.to, to: $0.from) }
    }

    private static func move(_ op: RenameOp) throws {
        let fm = FileManager.default
        guard op.from != op.to else { return }

        // Cambio solo de mayúsculas/minúsculas: en volúmenes insensibles a ello
        // el destino "existe" (es el propio fichero), así que se pasa por un nombre temporal.
        if op.from.path.caseInsensitiveCompare(op.to.path) == .orderedSame {
            let temp = op.from.deletingLastPathComponent()
                .appendingPathComponent(".mediarenamer-\(UUID().uuidString)")
            try fm.moveItem(at: op.from, to: temp)
            do {
                try fm.moveItem(at: temp, to: op.to)
            } catch {
                try? fm.moveItem(at: temp, to: op.from)
                throw error
            }
            return
        }

        if fm.fileExists(atPath: op.to.path) {
            throw RenameError.destinationExists(op.to.lastPathComponent)
        }
        try fm.moveItem(at: op.from, to: op.to)
    }
}

/// Descubrimiento de ficheros de vídeo (ficheros sueltos o carpetas).
enum MediaFileScanner {
    static let videoExtensions: Set<String> = ["mkv", "mp4", "avi", "mov", "m4v", "wmv", "ts", "m2ts", "mpg", "mpeg", "flv", "webm"]

    /// Devuelve los vídeos de `url`; si es una carpeta, los busca recursivamente
    /// ignorando ficheros ocultos y paquetes.
    static func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }

        guard isDirectory.boolValue else {
            return videoExtensions.contains(url.pathExtension.lowercased()) ? [url] : []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
    }
}
