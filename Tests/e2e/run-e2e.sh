#!/bin/bash
# Prueba de extremo a extremo con una carpeta de series y un TMDb simulado en local:
# buscar → elegir a mano → propagar → renombrar → deshacer, y comprueba que el disco queda igual.
# No toca el Llavero real ni la red. Uso: Tests/e2e/run-e2e.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
W="$(mktemp -d)"; SRC="$W/src"; S="$W/Series"; mkdir -p "$SRC"
trap 'pkill -f "$W/mock_tmdb.py" 2>/dev/null || true' EXIT

# Fuentes de la app (sin vistas) con la URL de TMDb apuntando al mock y Llavero en memoria.
cp MediaRenamer/Models/*.swift "$SRC/"
cp MediaRenamer/Services/{FilenameParser,FilenameBuilder,FileRenamer,TMDbClient,RenameEngine}.swift "$SRC/"
cp Tests/e2e/main.swift Tests/e2e/KeychainStub.swift "$SRC/"
sed -i '' 's#https://api.themoviedb.org/3#http://127.0.0.1:8765/3#' "$SRC/TMDbClient.swift"
swiftc -o "$W/e2e" "$SRC"/*.swift

# Carpeta de prueba
mk(){ mkdir -p "$(dirname "$S/$1")"; : > "$S/$1"; }
for i in 1 2 3; do mk "Breaking Bad (2008)/Season 1/Breaking.Bad.S01E0$i.720p.BluRay.x264.mkv"; done
mk "Breaking Bad (2008)/Season 1/Breaking.Bad.S01E01.720p.BluRay.x264.es.srt"
mk "Breaking Bad (2008)/Season 1/Breaking.Bad.S01E01.720p.BluRay.x264.srt"
mk "Mi Serie/Temporada 1/01.mkv"; mk "Mi Serie/Temporada 1/02.mkv"
mk "The.Office.US.S02E03.1080p.WEB-DL.mkv"; mk "The.Office.US.S02E04.1080p.WEB-DL.mkv"
mk "Fargo.s01e01.HDTV.mkv"; mk "Fargo.s01e02.HDTV.mkv"
mk "Dark.Matter.S01E01E02.mkv"; mk "Nonexistent.Show.S01E01.mkv"
mk "Dup.Show.S01E01.720p.mkv"; mk "Dup.Show.S01E01.1080p.mkv"
mk "Sneaky.S01E01.mkv"; mk "sneaky.s01e02.mkv"
mk ".hidden/Ignorame.S01E01.mkv"; mk "notes.txt"
cp -R "$S" "$W/Series.orig"

cp Tests/e2e/mock_tmdb.py "$W/mock_tmdb.py"
python3 "$W/mock_tmdb.py" 2> "$W/mock.log" &
sleep 1

"$W/e2e" "$S" | tee "$W/out.txt"
grep -q "renombrados: 12; deshechos -> 12" "$W/out.txt"
grep -q "Descubiertos: 15" "$W/out.txt"
grep -q "Materia Oscura - S01E01-E02 - Despertar.mkv" "$W/out.txt"
grep -q "Mi Serie - S01E02 - Dos.mkv" "$W/out.txt"
diff -r "$S" "$W/Series.orig"
echo "E2E OK: la carpeta quedó idéntica tras deshacer"
