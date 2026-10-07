#!/bin/bash
# Genera dist/MediaRenamer-<versión>.dmg (binario universal, firma ad-hoc + hardened runtime).
# Para distribución sin avisos de Gatekeeper hace falta firmar con Developer ID y notarizar.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' MediaRenamer.xcodeproj/project.pbxproj | head -1)
rm -rf build/Release dist && mkdir -p dist/stage

xcodebuild -project MediaRenamer.xcodeproj -scheme MediaRenamer -configuration Release \
  -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  CONFIGURATION_BUILD_DIR="$PWD/build/Release" build | tail -1

cp -R build/Release/MediaRenamer.app dist/stage/
ln -s /Applications dist/stage/Applications
cat > dist/stage/LEEME.txt <<TXT
MediaRenamer $VERSION

Instalación: arrastra MediaRenamer a Aplicaciones.

La app está firmada ad-hoc (sin Developer ID), así que Gatekeeper la bloqueará la primera vez:
  - Clic derecho sobre la app > Abrir > Abrir, o
  - Ajustes del Sistema > Privacidad y seguridad > "Abrir igualmente", o
  - Terminal: xattr -dr com.apple.quarantine /Applications/MediaRenamer.app

Necesitas una API key gratuita de TMDb (Ajustes, ⌘,).
TXT

hdiutil create -volname "MediaRenamer $VERSION" -srcfolder dist/stage -ov -format UDZO "dist/MediaRenamer-$VERSION.dmg"
(cd dist && shasum -a 256 "MediaRenamer-$VERSION.dmg" > "MediaRenamer-$VERSION.dmg.sha256")
rm -rf dist/stage
echo "Listo: dist/MediaRenamer-$VERSION.dmg"
