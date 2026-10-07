import Foundation
// realpath (no resolvingSymlinksInPath, que quita el prefijo /private) para que
// la ruta coincida con la que devuelve el enumerador de ficheros.
let root = URL(fileURLWithPath: realpath(CommandLine.arguments[1], nil).map { String(cString: $0) } ?? CommandLine.arguments[1])
let engine = RenameEngine()
let lib = LibraryModel()
AppSettings.shared.apiKey = "testkey"
@MainActor func show(_ t: String) {
    print("\n== \(t)")
    for i in lib.items {
        let rel = i.originalURL.path.replacingOccurrences(of: root.path + "/", with: "")
        print("  [\(i.status)] \(rel)  -> \(i.proposedFilename ?? "-")  (\(i.parsedTitle)|S\(i.season.map(String.init) ?? "?")E\(i.episode.map(String.init) ?? "?")) \(i.warning ?? "")")
    }
}
lib.add(MediaFileScanner.expand(root))
print("Descubiertos: \(lib.items.count)")
let t0 = Date()
await engine.searchAll(lib.items) { d, t in if d == t { print("progreso \(d)/\(t)") } }
print(String(format: "búsqueda: %.1fs", Date().timeIntervalSince(t0)))
show("Tras buscar")

// Elegir a mano la serie ambigua "The Office US" (candidato US) y propagar
let office = lib.items.first { $0.parsedTitle.lowercased().hasPrefix("the office") }!
await engine.select(candidate: office.candidates[0], for: office, manual: true)
await engine.propagateToSeries(from: office, candidate: office.candidates[0], in: lib.items)
let fargo = lib.items.first { $0.parsedTitle == "Fargo" }!
await engine.select(candidate: fargo.candidates[0], for: fargo, manual: true)
await engine.propagateToSeries(from: fargo, candidate: fargo.candidates[0], in: lib.items)
show("Tras elegir Office y Fargo")

engine.renameAll(lib.items)
show("Tras renombrar")
let n = lib.items.filter { $0.status == .renamed }.count
engine.undoAll(lib.items)
print("\nrenombrados: \(n); deshechos -> \(lib.items.filter { $0.status == .autoMatched }.count) listos de nuevo")
