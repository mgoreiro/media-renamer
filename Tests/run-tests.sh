#!/bin/bash
# Compila y ejecuta las pruebas de la lógica pura (parser, builder, renombrador).
set -euo pipefail
cd "$(dirname "$0")/.."
# Necesita MediaKind (definido en MediaItem.swift): se extrae de un stub mínimo.
OUT="$(mktemp -d)"
cat > "$OUT/Stub.swift" <<'SWIFT'
enum MediaKind: String, Codable { case movie, episode, unknown }
SWIFT
swiftc -o "$OUT/tests" "$OUT/Stub.swift" \
  MediaRenamer/Services/FilenameParser.swift \
  MediaRenamer/Services/FilenameBuilder.swift \
  MediaRenamer/Services/FileRenamer.swift \
  Tests/main.swift
"$OUT/tests"
