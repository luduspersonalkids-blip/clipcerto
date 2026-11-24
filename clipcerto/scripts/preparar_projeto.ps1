# Prepara o projeto ClipCerto no Windows (PowerShell).
# Execute DENTRO da pasta do projeto:  .\scripts\preparar_projeto.ps1
#
# O que faz:
#  1. Gera as pastas nativas (android e windows) com o "flutter create".
#     Arquivos que já existem (lib, pubspec, testes) NÃO são sobrescritos.
#  2. Copia o código nativo do ClipCerto para dentro da pasta android.
#  3. Baixa as dependências.

$ErrorActionPreference = "Stop"

Write-Host "1/3 Gerando pastas nativas..." -ForegroundColor Cyan
flutter create --org br.com.ludus --project-name clipcerto --platforms android,windows .

Write-Host "2/3 Copiando codigo nativo do Android..." -ForegroundColor Cyan
$kotlinDir = "android\app\src\main\kotlin\br\com\ludus\clipcerto"
New-Item -ItemType Directory -Force -Path $kotlinDir | Out-Null
Copy-Item -Force "native_android\MainActivity.kt" "$kotlinDir\MainActivity.kt"
Copy-Item -Force "native_android\AndroidManifest.xml" "android\app\src\main\AndroidManifest.xml"

Write-Host "3/3 Baixando dependencias..." -ForegroundColor Cyan
flutter pub get

Write-Host "Pronto! Teste com: flutter run" -ForegroundColor Green
