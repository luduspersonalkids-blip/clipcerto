#!/usr/bin/env bash
# Prepara o projeto ClipCerto (Linux, macOS ou GitHub Actions).
# Execute dentro da pasta do projeto:  bash scripts/preparar_projeto.sh
set -euo pipefail

echo "1/3 Gerando pastas nativas..."
flutter create --org br.com.ludus --project-name clipcerto --platforms android,windows .

echo "2/3 Copiando codigo nativo do Android..."
KOTLIN_DIR="android/app/src/main/kotlin/br/com/ludus/clipcerto"
mkdir -p "$KOTLIN_DIR"
cp -f native_android/MainActivity.kt "$KOTLIN_DIR/MainActivity.kt"
cp -f native_android/AndroidManifest.xml android/app/src/main/AndroidManifest.xml

echo "3/3 Baixando dependencias..."
flutter pub get

echo "Pronto!"
