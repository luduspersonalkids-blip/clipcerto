// Integração OPCIONAL com a API oficial do Instagram (Instagram API with Instagram Login).
//
// O que ela permite: listar as mídias da SUA conta profissional (Business ou Criador de
// conteúdo) e obter o endereço oficial do arquivo (media_url) para salvar.
// O que ela NÃO permite: acessar mídias, Reels ou Stories de outras pessoas.
//
// Stories: a Meta documenta o endpoint /stories (somente Stories das últimas 24 horas).
// Dependendo do tipo de login configurado no seu app da Meta, ele pode não estar
// disponível; nesse caso o app mostra a mensagem de erro da própria API.
//
// Pré-requisitos (feitos no site developers.facebook.com, sem custo):
//  1) conta do Instagram do tipo Profissional;
//  2) um app da Meta com o produto "Instagram" (API com login do Instagram);
//  3) sua conta adicionada como testadora do app;
//  4) um token de acesso gerado no painel do app e colado no ClipCerto.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class IgMedia {
  final String id;
  final String mediaType; // VIDEO, IMAGE ou CAROUSEL_ALBUM
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? permalink;
  final String? caption;
  final DateTime? timestamp;
  final bool isStory;

  IgMedia({
    required this.id,
    required this.mediaType,
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.permalink,
    required this.caption,
    required this.timestamp,
    required this.isStory,
  });

  bool get isVideo => mediaType == 'VIDEO';
  bool get canSave => mediaUrl != null && mediaType != 'CAROUSEL_ALBUM';

  String get previewUrl => thumbnailUrl ?? (isVideo ? '' : (mediaUrl ?? ''));

  String get suggestedFileName {
    final date = timestamp ?? DateTime.now();
    final d = '${date.year}${_two(date.month)}${_two(date.day)}';
    final prefix = isStory ? 'story' : (isVideo ? 'reel' : 'foto');
    return 'instagram_${prefix}_${d}_$id.${isVideo ? 'mp4' : 'jpg'}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  factory IgMedia.fromJson(Map<String, dynamic> j, {required bool isStory}) => IgMedia(
        id: j['id'].toString(),
        mediaType: (j['media_type'] as String?) ?? 'IMAGE',
        mediaUrl: j['media_url'] as String?,
        thumbnailUrl: j['thumbnail_url'] as String?,
        permalink: j['permalink'] as String?,
        caption: j['caption'] as String?,
        timestamp: DateTime.tryParse((j['timestamp'] as String?) ?? ''),
        isStory: isStory,
      );
}

class InstagramApiException implements Exception {
  final String message;
  InstagramApiException(this.message);
  @override
  String toString() => message;
}

class InstagramService {
  static const _host = 'graph.instagram.com';
  static const _version = 'v25.0';
  static const _fields =
      'id,media_type,media_url,thumbnail_url,permalink,caption,timestamp';

  final String accessToken;
  final http.Client _client = http.Client();

  InstagramService(this.accessToken);

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final uri = Uri.https(_host, '/$_version$path', {...query, 'access_token': accessToken});
    http.Response resp;
    try {
      resp = await _client.get(uri).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw InstagramApiException('O Instagram demorou para responder. Tente de novo.');
    } on SocketException {
      throw InstagramApiException('Sem conexão com a internet.');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw InstagramApiException('Resposta inesperada do Instagram (${resp.statusCode}).');
    }
    if (resp.statusCode != 200 || body.containsKey('error')) {
      final err = body['error'];
      final msg = err is Map ? (err['message'] ?? 'erro desconhecido') : 'erro ${resp.statusCode}';
      final code = err is Map ? err['code'] : null;
      // Código 190 = token inválido/expirado na Graph API da Meta.
      if (code == 190 || msg.toString().toLowerCase().contains('token')) {
        throw InstagramApiException(
            'Token inválido ou expirado. Gere um novo token no painel da Meta. Detalhe: $msg');
      }
      throw InstagramApiException('O Instagram recusou a solicitação: $msg');
    }
    return body;
  }

  /// Confere o token e devolve o nome de usuário (@).
  Future<String> fetchUsername() async {
    final body = await _get('/me', {'fields': 'user_id,username'});
    return (body['username'] as String?) ?? 'sua conta';
  }

  /// Publicações e Reels da própria conta (até [limit] itens).
  Future<List<IgMedia>> fetchMyMedia({int limit = 50}) async {
    final body = await _get('/me/media', {'fields': _fields, 'limit': '$limit'});
    final data = (body['data'] as List<dynamic>? ?? []);
    return data.map((e) => IgMedia.fromJson(e as Map<String, dynamic>, isStory: false)).toList();
  }

  /// Stories ativos (últimas 24 horas) da própria conta.
  Future<List<IgMedia>> fetchMyStories() async {
    final body = await _get('/me/stories', {'fields': _fields});
    final data = (body['data'] as List<dynamic>? ?? []);
    return data.map((e) => IgMedia.fromJson(e as Map<String, dynamic>, isStory: true)).toList();
  }

  void dispose() => _client.close();
}
