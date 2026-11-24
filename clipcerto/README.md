# ClipCerto

Aplicativo para Android e Windows que organiza e salva vídeos **que você tem direito de guardar**, sempre pelos caminhos permitidos por cada plataforma.

## 1. O que o app faz

| Recurso | Situação |
|---|---|
| Colar link (botão Colar ou digitar) | Implementado |
| Receber link pelo menu Compartilhar do Android | Implementado (código nativo em `native_android/MainActivity.kt`) |
| Identificar YouTube, TikTok, Instagram (Reel, Story, Short, publicação, perfil) | Implementado |
| Abrir o conteúdo no app oficial ou no navegador | Implementado |
| Guardar links na Biblioteca | Implementado |
| Salvar arquivo de mídia acessível diretamente (ex.: `.mp4` no seu site ou servidor) | Implementado, com confirmação de direitos, progresso e cancelamento |
| Salvar Reels, publicações e Stories da **sua** conta profissional do Instagram | Implementado, **depende da API oficial da Meta e do seu token** |
| Stories da sua conta pela API | Depende da configuração do seu app na Meta; o app mostra o erro da API se não estiver disponível |
| Baixar vídeos do YouTube | **Não oferecido**: o YouTube não libera o arquivo para terceiros. O app orienta o caminho oficial (YouTube Studio para vídeos seus, Download do Premium dentro do app) |
| Baixar vídeos do TikTok | **Não oferecido pelo app**: o próprio TikTok tem "Salvar vídeo" quando o criador permite. O app abre o vídeo no TikTok |
| Baixar Reels ou Stories de outras pessoas no Instagram | **Não oferecido**: sem API para isso. O app orienta pedir o arquivo ao titular |

O app **não** lê páginas para extrair endereços escondidos, **não** contorna DRM, login, conteúdo privado ou bloqueio de download.

## 2. Estrutura do projeto

```
clipcerto/
  pubspec.yaml                  dependências
  lib/
    main.dart                   tema e navegação (barra inferior no celular, menu lateral no PC)
    models/saved_item.dart      dados de arquivos salvos e links guardados
    services/
      link_analyzer.dart        identifica plataforma, tipo e nome de arquivo
      download_service.dart     download em fluxo com progresso e cancelamento
      native_bridge.dart        ponte com o Android (compartilhar, pasta, abrir, enviar)
      instagram_service.dart    API oficial do Instagram (somente sua conta)
      app_state.dart            estado central: pasta, histórico, token, progresso
    screens/                    Início, Biblioteca, Minha conta, Ajustes
    widgets/                    confirmação, progresso, cores e orientações por plataforma
  native_android/
    MainActivity.kt             código nativo Android (vai para android/app/src/main/kotlin/...)
    AndroidManifest.xml         permissões e filtro do menu Compartilhar
  scripts/
    preparar_projeto.ps1        prepara tudo no Windows
    preparar_projeto.sh         prepara tudo no Linux/macOS/GitHub
  test/                         testes automáticos
  .github/workflows/gerar-apk.yml  compila APK e versão Windows na nuvem
```

## 3. Opção A: gerar o APK na nuvem (sem instalar Android Studio)

1. Crie uma conta gratuita em github.com e um repositório novo (pode ser privado).
2. Envie todos os arquivos desta pasta para o repositório (botão "Add file" > "Upload files", arrastando a pasta inteira, inclusive a pasta `.github`).
3. Abra a aba **Actions** > **Gerar APK e Windows** > **Run workflow**.
4. Aguarde cerca de 10 minutos. Ao terminar, abra a execução e baixe **ClipCerto-android** (dentro do zip está o `app-release.apk`) e **ClipCerto-windows**.

Repositórios públicos têm Actions gratuito; privados têm uma cota mensal gratuita, suficiente para este projeto.

## 4. Opção B: compilar no seu computador Windows

### Pré-requisitos (uma vez só)
1. **Flutter SDK** (estável): https://docs.flutter.dev/get-started/install/windows  
   Descompacte em `C:\flutter` e adicione `C:\flutter\bin` ao PATH.
2. **Android Studio**: instale e, no primeiro uso, deixe instalar o Android SDK. Em *SDK Manager > SDK Tools*, marque **Android SDK Command-line Tools**.
3. **Visual Studio 2022 Community** com a carga "Desenvolvimento para desktop com C++" (apenas para a versão Windows).
4. No PowerShell:
   ```powershell
   flutter doctor --android-licenses
   flutter doctor
   ```
   Corrija o que aparecer com X vermelho.

### Preparar e testar
```powershell
cd C:\caminho\para\clipcerto
powershell -ExecutionPolicy Bypass -File .\scripts\preparar_projeto.ps1
flutter test                # testes automáticos
flutter run -d windows      # abre no computador
flutter run                 # abre no celular conectado por USB (depuração USB ligada)
```

### Gerar o APK
```powershell
flutter build apk --release
```
O arquivo é criado em:
```
build\app\outputs\flutter-apk\app-release.apk
```
Para um APK menor, específico para cada processador: `flutter build apk --split-per-abi` (use o `arm64-v8a` na maioria dos celulares atuais).

### Gerar a versão Windows
```powershell
flutter build windows --release
```
Resultado: pasta `build\windows\x64\runner\Release` (copie a pasta inteira; o executável é `clipcerto.exe`).

## 5. Instalar o APK no celular

1. Envie o `app-release.apk` para o celular (cabo USB, Google Drive, WhatsApp para você mesmo).
2. Toque no arquivo. O Android pedirá para permitir "Instalar apps desconhecidos" para o app que abriu o arquivo (Arquivos, Drive...). Permita só para essa instalação.
3. Toque em Instalar.

Ou, com o celular conectado por USB: `adb install build\app\outputs\flutter-apk\app-release.apk`

> O APK de release usa a assinatura de depuração gerada pelo Flutter: serve para instalar nos seus aparelhos. Para publicar na Play Store, crie uma chave própria (https://docs.flutter.dev/deployment/android#signing-the-app).

## 6. Roteiro de teste

1. Abra o app, vá em **Ajustes** e escolha a pasta de destino (no Android, crie `Movies/ClipCerto` no próprio seletor).
2. Em **Início**, cole um link de arquivo `.mp4` público de sua propriedade e toque em **Analisar** > **Verificar e salvar**. Confirme os direitos e acompanhe o progresso.
3. Veja o arquivo em **Biblioteca** e use Abrir e Compartilhar.
4. No app do YouTube, TikTok ou Instagram, toque em **Compartilhar** > **ClipCerto**. O link chega na tela inicial já analisado.
5. Feche e abra o app: a pasta continua a mesma.
6. Teste erro: cole um link de página comum (ex.: um site de notícias). O app deve recusar com explicação.

## 7. Instagram: conectar a sua conta (opcional)

1. Converta sua conta para Profissional (Configurações > Tipo de conta e ferramentas).
2. Em https://developers.facebook.com crie um app, adicione o produto **Instagram** e escolha **API com login do Instagram**.
3. Em **Funções do app**, adicione sua conta do Instagram como **Testadora** e aceite o convite no Instagram (Configurações > Apps e sites).
4. Na configuração da API, gere o token de acesso da sua conta.
5. No ClipCerto, aba **Minha conta**, cole o token.

Custos e limites: criar o app na Meta é gratuito; uso pessoal como testador dispensa revisão da Meta; para outras pessoas usarem, é necessária a revisão do app pela Meta. O token expira e precisa ser renovado. O token fica salvo apenas no aparelho (para mais segurança em uma versão futura, use `flutter_secure_storage`).

## 8. Próximos passos sugeridos

- Ícone e tela de abertura personalizados (`flutter_launcher_icons`).
- Renovação automática do token do Instagram.
- Fila com vários downloads.
- Login OAuth completo do Instagram (em vez de colar o token), necessário se o app for usado por outras pessoas.
