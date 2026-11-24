// Analisa o texto colado ou compartilhado e descobre:
// 1) qual é o link (o TikTok, por exemplo, compartilha "texto + link");
// 2) de qual plataforma ele é;
// 3) o que o ClipCerto pode fazer com ele DE FORMA PERMITIDA.
//
// Regra central do app: links de YouTube, TikTok e Instagram NUNCA são
// "raspados" nem baixados direto. Para eles, o app orienta o caminho oficial.
// Download direto só acontece para endereços que apontam para um ARQUIVO
// de mídia (ex.: .mp4 no seu servidor, no seu Drive público, etc.)
// ou para a SUA própria mídia obtida pela API oficial do Instagram.

enum SourcePlatform { youtube, tiktok, instagram, directFile, webPage }

class LinkAnalysis {
  final Uri uri;
  final SourcePlatform platform;

  /// Tipo de conteúdo detectado: "Short", "Reel", "Story", "Vídeo", "Arquivo de vídeo"...
  final String kind;

  /// Nome amigável da plataforma para exibir na tela.
  final String platformName;

  /// true quando o app pode tentar salvar o arquivo diretamente.
  final bool canSaveDirectly;

  const LinkAnalysis({
    required this.uri,
    required this.platform,
    required this.kind,
    required this.platformName,
    required this.canSaveDirectly,
  });
}

class LinkAnalyzer {
  static final RegExp _urlRegex = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);

  static const _mediaExtensions = {
    'mp4', 'm4v', 'mov', 'webm', 'mkv', '3gp',
    'mp3', 'm4a', 'aac', 'wav', 'ogg',
    'jpg', 'jpeg', 'png', 'webp', 'gif',
  };

  /// Pega o primeiro endereço http(s) dentro de um texto qualquer.
  static String? extractFirstUrl(String text) {
    final match = _urlRegex.firstMatch(text.trim());
    if (match == null) return null;
    // Remove pontuação que costuma "grudar" no fim do link em mensagens.
    var url = match.group(0)!;
    while (url.isNotEmpty && '.,;:!?)]}'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Devolve null quando não há link válido no texto.
  static LinkAnalysis? analyze(String rawText) {
    final url = extractFirstUrl(rawText);
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;

    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.)'), '');
    final path = uri.path.toLowerCase();

    // ---------- YouTube ----------
    if (host == 'youtu.be' || host.endsWith('youtube.com') || host == 'youtube-nocookie.com') {
      String kind = 'Vídeo';
      if (path.startsWith('/shorts/')) kind = 'Short';
      if (path.startsWith('/live/')) kind = 'Live';
      if (path.startsWith('/playlist')) kind = 'Playlist';
      if (path.startsWith('/@') || path.startsWith('/channel/') || path.startsWith('/c/')) {
        kind = 'Canal';
      }
      return LinkAnalysis(
        uri: uri,
        platform: SourcePlatform.youtube,
        kind: kind,
        platformName: 'YouTube',
        canSaveDirectly: false,
      );
    }

    // ---------- TikTok ----------
    if (host.endsWith('tiktok.com')) {
      String kind = 'Vídeo';
      if (host.startsWith('vm.') || host.startsWith('vt.')) kind = 'Vídeo (link curto)';
      if (path.contains('/photo/')) kind = 'Foto';
      if (path.startsWith('/@') && !path.contains('/video/') && !path.contains('/photo/')) {
        kind = 'Perfil';
      }
      return LinkAnalysis(
        uri: uri,
        platform: SourcePlatform.tiktok,
        kind: kind,
        platformName: 'TikTok',
        canSaveDirectly: false,
      );
    }

    // ---------- Instagram ----------
    if (host.endsWith('instagram.com') || host == 'instagr.am') {
      String kind = 'Perfil';
      if (path.startsWith('/reel/') || path.startsWith('/reels/')) kind = 'Reel';
      if (path.startsWith('/p/')) kind = 'Publicação';
      if (path.startsWith('/tv/')) kind = 'Vídeo';
      if (path.startsWith('/stories/')) kind = 'Story';
      return LinkAnalysis(
        uri: uri,
        platform: SourcePlatform.instagram,
        kind: kind,
        platformName: 'Instagram',
        canSaveDirectly: false,
      );
    }

    // ---------- Arquivo direto (termina em .mp4, .mov, .jpg...) ----------
    final ext = fileExtension(path);
    if (ext != null && _mediaExtensions.contains(ext)) {
      return LinkAnalysis(
        uri: uri,
        platform: SourcePlatform.directFile,
        kind: 'Arquivo .$ext',
        platformName: 'Arquivo direto',
        canSaveDirectly: true,
      );
    }

    // ---------- Qualquer outro endereço ----------
    // Pode ser um arquivo sem extensão (o app confere o tipo antes de salvar)
    // ou uma página comum (nesse caso o app avisa e não salva).
    return LinkAnalysis(
      uri: uri,
      platform: SourcePlatform.webPage,
      kind: 'Endereço web',
      platformName: 'Outro site',
      canSaveDirectly: true,
    );
  }

  /// Extensão do caminho, em minúsculas, sem o ponto. Ex.: "/a/b/video.MP4" -> "mp4".
  static String? fileExtension(String path) {
    final lastSegment = path.split('/').last;
    final dot = lastSegment.lastIndexOf('.');
    if (dot <= 0 || dot == lastSegment.length - 1) return null;
    return lastSegment.substring(dot + 1).toLowerCase();
  }

  /// Sugere um nome de arquivo seguro para Windows e Android.
  static String suggestFileName(Uri uri, {String? contentType}) {
    var base = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    base = Uri.decodeComponent(base);
    if (base.isEmpty) base = 'clipcerto_${DateTime.now().millisecondsSinceEpoch}';
    base = sanitizeFileName(base);
    if (fileExtension(base) == null) {
      final ext = extensionForMime(contentType) ?? 'mp4';
      base = '$base.$ext';
    }
    return base;
  }

  /// Troca caracteres proibidos em nomes de arquivo e limita o tamanho.
  static String sanitizeFileName(String name) {
    var clean = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    clean = clean.replaceAll(RegExp(r'\s+'), ' ');
    while (clean.startsWith('.')) {
      clean = clean.substring(1);
    }
    if (clean.length > 90) {
      final ext = fileExtension(clean);
      final keep = 90 - (ext == null ? 0 : ext.length + 1);
      clean = clean.substring(0, keep) + (ext == null ? '' : '.$ext');
    }
    return clean.isEmpty ? 'arquivo' : clean;
  }

  static String? extensionForMime(String? mime) {
    if (mime == null) return null;
    final m = mime.split(';').first.trim().toLowerCase();
    const map = {
      'video/mp4': 'mp4',
      'video/quicktime': 'mov',
      'video/webm': 'webm',
      'video/x-matroska': 'mkv',
      'video/3gpp': '3gp',
      'audio/mpeg': 'mp3',
      'audio/mp4': 'm4a',
      'audio/aac': 'aac',
      'audio/wav': 'wav',
      'audio/ogg': 'ogg',
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/gif': 'gif',
    };
    return map[m];
  }

  static String mimeForFileName(String name) {
    const map = {
      'mp4': 'video/mp4',
      'm4v': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'mkv': 'video/x-matroska',
      '3gp': 'video/3gpp',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
    };
    return map[fileExtension(name) ?? ''] ?? 'application/octet-stream';
  }

  /// true se o tipo informado pelo servidor é de mídia (vídeo, áudio ou imagem).
  static bool isMediaMime(String? mime) {
    if (mime == null) return false;
    final m = mime.toLowerCase();
    return m.startsWith('video/') || m.startsWith('audio/') || m.startsWith('image/');
  }
}
