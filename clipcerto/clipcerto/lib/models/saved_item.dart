// Modelos de dados do ClipCerto.
// SavedItem = arquivo que já foi salvo com sucesso.
// SavedLink = link guardado na biblioteca para abrir depois no app oficial.

import 'dart:convert';

class SavedItem {
  final String id;
  final String fileName;

  /// No computador: caminho completo do arquivo (C:\...\video.mp4).
  /// No Android: endereço content:// devolvido pelo sistema (pasta escolhida pelo usuário).
  final String location;
  final String mimeType;
  final String sourceUrl;
  final String platform;
  final DateTime savedAt;
  final int sizeBytes;

  SavedItem({
    required this.id,
    required this.fileName,
    required this.location,
    required this.mimeType,
    required this.sourceUrl,
    required this.platform,
    required this.savedAt,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'location': location,
        'mimeType': mimeType,
        'sourceUrl': sourceUrl,
        'platform': platform,
        'savedAt': savedAt.toIso8601String(),
        'sizeBytes': sizeBytes,
      };

  factory SavedItem.fromJson(Map<String, dynamic> j) => SavedItem(
        id: j['id'] as String,
        fileName: j['fileName'] as String,
        location: j['location'] as String,
        mimeType: (j['mimeType'] as String?) ?? 'application/octet-stream',
        sourceUrl: (j['sourceUrl'] as String?) ?? '',
        platform: (j['platform'] as String?) ?? 'Arquivo',
        savedAt: DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      );

  static String encodeList(List<SavedItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<SavedItem> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => SavedItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}

class SavedLink {
  final String url;
  final String platform;
  final String kind;
  final DateTime savedAt;

  SavedLink({
    required this.url,
    required this.platform,
    required this.kind,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'platform': platform,
        'kind': kind,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedLink.fromJson(Map<String, dynamic> j) => SavedLink(
        url: j['url'] as String,
        platform: (j['platform'] as String?) ?? 'Link',
        kind: (j['kind'] as String?) ?? '',
        savedAt: DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      );

  static String encodeList(List<SavedLink> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<SavedLink> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => SavedLink.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
