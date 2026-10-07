import Foundation

// Mini arnés de pruebas sin XCTest: se compila junto a las fuentes puras.
// Ejecutar con Tests/run-tests.sh
var failures = 0
func check<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: Int = #line) {
    if actual != expected { failures += 1; print("FAIL [\(line)] \(label): got \(actual), expected \(expected)") }
}

func p(_ f: String) -> ParsedFilename { FilenameParser.parse(filename: f) }

// Películas
var r = p("The.Matrix.1999.1080p.BluRay.x264.mkv")
check(r.title, "The Matrix", "matrix title"); check(r.year, 1999, "matrix year"); check(r.kind, .movie, "matrix kind")
r = p("Webster.Cambio.Espana.mkv"); check(r.title, "Webster Cambio Espana", "junk como subcadena")
r = p("Engaño.2015.720p.mkv"); check(r.title, "Engaño", "engaño"); check(r.year, 2015, "engaño year")
r = p("1917.2019.1080p.BluRay.mkv"); check(r.title, "1917", "1917 title"); check(r.year, 2019, "1917 year")
r = p("1917.1080p.BluRay.mkv"); check(r.title, "1917", "1917 sin año"); check(r.year, nil, "1917 sin año year")
r = p("2012 (2009) 1080p.mkv"); check(r.title, "2012", "2012 title"); check(r.year, 2009, "2012 year")
r = p("Blade Runner 2049 (2017).mkv"); check(r.title, "Blade Runner 2049", "br2049"); check(r.year, 2017, "br2049 year")
r = p("Movie.Name.1080p.mkv"); check(r.title, "Movie Name", "solo junk")
r = p("[YTS] Movie Name (2020) [1080p].mp4"); check(r.title, "Movie Name", "grupo"); check(r.year, 2020, "grupo year")
r = p("Solo Titulo.mkv"); check(r.title, "Solo Titulo", "simple"); check(r.kind, .movie, "simple kind")

// Episodios
r = p("breaking.bad.s01e02.720p.hdtv.mkv")
check(r.title, "breaking bad", "bb"); check(r.season, 1, "bb s"); check(r.episode, 2, "bb e"); check(r.kind, .episode, "bb kind")
r = p("Show Name 1x05 HDTV.avi"); check(r.title, "Show Name", "nxm"); check(r.season, 1, "nxm s"); check(r.episode, 5, "nxm e")
r = p("Show.1920x1080.mkv"); check(r.kind, .movie, "1920x1080 no es episodio")
r = p("Show Season 2 Episode 10.mkv"); check(r.season, 2, "long s"); check(r.episode, 10, "long e"); check(r.title, "Show", "long title")
r = p("Serie S01E01E02 720p.mkv"); check(r.episode, 1, "multi e"); check(r.episodeEnd, 2, "multi end")
r = p("Serie S01E01-E03.mkv"); check(r.episodeEnd, 3, "multi guion")
r = p("Serie S01E01 - 1080p.mkv"); check(r.episodeEnd, nil, "no confundir resolución")
r = p("Show (2019) S02E03.mkv"); check(r.year, 2019, "serie año"); check(r.title, "Show", "serie año title")
r = p("Show S01E01 2015 Remastered.mkv"); check(r.year, nil, "año tras episodio ignorado")

// Contexto de carpeta
func u(_ s: String) -> ParsedFilename { FilenameParser.parse(url: URL(fileURLWithPath: s)) }
r = u("/tv/Mi Serie (2018)/Season 2/03.mkv"); check(r.title, "Mi Serie", "carpeta title"); check(r.season, 2, "carpeta s"); check(r.episode, 3, "carpeta e"); check(r.year, 2018, "carpeta year")
r = u("/tv/Otra Serie/Temporada 1/S01E04.mkv"); check(r.title, "Otra Serie", "carpeta 2")
r = u("/movies/Peli Genial (2001)/video.mkv"); check(r.title, "video", "nombre con título gana")
r = u("/movies/Peli Genial (2001)/1080p.mkv"); check(r.title, "Peli Genial", "título de carpeta"); check(r.year, 2001, "año de carpeta")

// Builder
func b(_ kind: MediaKind, _ t: String, y: Int? = nil, s: Int? = nil, e: Int? = nil, end: Int? = nil, et: String? = nil, ext: String = "mkv") -> String {
    FilenameBuilder.build(kind: kind, title: t, year: y, season: s, episode: e, episodeEnd: end, episodeTitle: et, ext: ext)
}
check(b(.movie, "The Matrix", y: 1999), "The Matrix (1999).mkv", "b movie")
check(b(.movie, "Mission: Impossible", y: 1996), "Mission - Impossible (1996).mkv", "b dos puntos")
check(b(.movie, "What? <Is> \"This\" | * \\ /", y: nil), "What Is 'This' - -.mkv", "b ilegales")
check(b(.movie, "...", y: nil), "Sin título.mkv", "b vacío")
check(b(.episode, "Show", s: 1, e: 2, et: "Pilot"), "Show - S01E02 - Pilot.mkv", "b ep")
check(b(.episode, "Show", s: 1, e: 2, end: 3), "Show - S01E02-E03.mkv", "b multi")
check(b(.episode, "Show", s: 1, e: 2, et: "Fin."), "Show - S01E02 - Fin.mkv", "b punto final")
let long = b(.movie, String(repeating: "á", count: 300), y: 2000)
check(long.utf8.count <= 255, true, "b longitud"); check(long.hasSuffix(".mkv"), true, "b longitud ext")

// Renombrador: plan, mayúsculas, subtítulos, rollback
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mr-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
func touch(_ n: String) { FileManager.default.createFile(atPath: tmp.appendingPathComponent(n).path, contents: Data()) }
func exists(_ n: String) -> Bool { (try? FileManager.default.contentsOfDirectory(atPath: tmp.path))?.contains(n) ?? false }

touch("old.name.2000.mkv"); touch("old.name.2000.srt"); touch("old.name.2000.es.srt"); touch("otro.srt")
var ops = FileRenamer.plan(source: tmp.appendingPathComponent("old.name.2000.mkv"), newName: "New (2000).mkv")
check(ops.count, 3, "plan con subtítulos")
try FileRenamer.perform(ops)
check(exists("New (2000).mkv") && exists("New (2000).srt") && exists("New (2000).es.srt") && exists("otro.srt"), true, "rename ok")
try FileRenamer.perform(FileRenamer.reversed(ops))
check(exists("old.name.2000.mkv") && exists("old.name.2000.es.srt") && !exists("New (2000).mkv"), true, "undo ok")

touch("foo.mkv")
ops = FileRenamer.plan(source: tmp.appendingPathComponent("foo.mkv"), newName: "Foo.mkv")
try FileRenamer.perform(ops)
check(exists("Foo.mkv") && !exists("foo.mkv"), true, "solo mayúsculas")

touch("a.mkv"); touch("a.srt"); touch("b.srt")
ops = [RenameOp(from: tmp.appendingPathComponent("a.mkv"), to: tmp.appendingPathComponent("z.mkv")),
       RenameOp(from: tmp.appendingPathComponent("a.srt"), to: tmp.appendingPathComponent("b.srt"))]
do { try FileRenamer.perform(ops); check(false, true, "debía fallar") } catch {}
check(exists("a.mkv") && exists("a.srt") && !exists("z.mkv"), true, "rollback")

print(failures == 0 ? "OK: todas las pruebas pasan" : "\(failures) fallo(s)")
exit(failures == 0 ? 0 : 1)
