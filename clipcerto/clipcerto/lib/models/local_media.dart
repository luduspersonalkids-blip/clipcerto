// Um vídeo ou áudio que já está no aparelho (galeria, pasta, ou salvo pelo ClipCerto).
//
// ref:
//  - Android: endereço content:// entregue pelo seletor do sistema ou pelo Compartilhar;
//  - Computador: caminho completo do arquivo (C:\...\video.mp4).

class LocalMedia {
  final String ref;
  final String name;
  final int size;
  final String mime;

  const LocalMedia({
    required this.ref,
    required this.name,
    required this.size,
    required this.mime,
  });

  bool get isVideo => mime.startsWith('video/');
  bool get isAudio => mime.startsWith('audio/');

  /// Nome sem a extensão, para montar "nome.m4a", "nome.txt" etc.
  String get baseName {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  factory LocalMedia.fromMap(Map<String, dynamic> m) => LocalMedia(
        ref: m['uri'] as String,
        name: (m['name'] as String?) ?? 'midia',
        size: (m['size'] as num?)?.toInt() ?? 0,
        mime: (m['mime'] as String?) ?? 'application/octet-stream',
      );
}
