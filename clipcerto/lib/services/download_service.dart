// Download em fluxo (streaming): o vídeo é gravado em pedaços no disco,
// sem ocupar a memória inteira do celular. Mostra progresso e permite cancelar.
//
// Este serviço baixa APENAS endereços que respondem com um arquivo de mídia
// (video/*, audio/*, image/*). Se o servidor devolver uma página (text/html),
// o download é recusado com uma mensagem clara. Não há leitura de páginas,
// extração de links escondidos nem qualquer contorno de proteção.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'link_analyzer.dart';

class DownloadException implements Exception {
  final String message;
  DownloadException(this.message);
  @override
  String toString() => message;
}

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download cancelado.';
}

class ProbeResult {
  final String? mimeType;
  final int? sizeBytes;
  final String suggestedName;
  final bool isMedia;

  ProbeResult({
    required this.mimeType,
    required this.sizeBytes,
    required this.suggestedName,
    required this.isMedia,
  });
}

class DownloadService {
  static const _userAgent = 'ClipCerto/1.0 (app pessoal de organizacao de midia)';
  final http.Client _client = http.Client();
  bool _cancelRequested = false;

  void cancel() => _cancelRequested = true;

  /// Consulta o servidor (sem baixar o arquivo) para saber tipo e tamanho.
  Future<ProbeResult> probe(Uri uri) async {
    http.BaseResponse resp;
    try {
      resp = await _client
          .send(http.Request('HEAD', uri)..headers['User-Agent'] = _userAgent)
          .timeout(const Duration(seconds: 20));
      // Alguns servidores não aceitam HEAD: tenta um GET e fecha logo após os cabeçalhos.
      if (resp.statusCode == 405 || resp.statusCode == 403 || resp.statusCode == 501) {
        final streamed = await _client
            .send(http.Request('GET', uri)..headers['User-Agent'] = _userAgent)
            .timeout(const Duration(seconds: 20));
        resp = streamed;
        // Lê nada do corpo: apenas cancela o fluxo.
        unawaited(streamed.stream.listen((_) {}).cancel());
      }
    } on TimeoutException {
      throw DownloadException('O servidor demorou demais para responder. Verifique sua internet.');
    } on SocketException {
      throw DownloadException('Sem conexão com a internet ou endereço inexistente.');
    } catch (e) {
      throw DownloadException('Não foi possível consultar o endereço: $e');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw DownloadException(
          'Acesso negado pelo servidor (${resp.statusCode}). Este conteúdo exige login ou autorização, '
          'e o ClipCerto não contorna controles de acesso.');
    }
    if (resp.statusCode == 404) {
      throw DownloadException('Arquivo não encontrado (404). O link pode ter expirado.');
    }
    if (resp.statusCode >= 400) {
      throw DownloadException('O servidor respondeu com erro ${resp.statusCode}.');
    }

    final mime = resp.headers['content-type'];
    final size = resp.contentLength;
    final fromDisposition = _nameFromDisposition(resp.headers['content-disposition']);
    final name = fromDisposition != null
        ? LinkAnalyzer.sanitizeFileName(fromDisposition)
        : LinkAnalyzer.suggestFileName(uri, contentType: mime);

    return ProbeResult(
      mimeType: mime,
      sizeBytes: (size != null && size > 0) ? size : null,
      suggestedName: name,
      isMedia: LinkAnalyzer.isMediaMime(mime) ||
          (mime == null || mime.contains('octet-stream')) &&
              LinkAnalyzer.fileExtension(uri.path) != null,
    );
  }

  /// Baixa [uri] para o arquivo [target]. Grava primeiro em "nome.part" e só
  /// renomeia ao final, para nunca deixar um arquivo pela metade com nome final.
  Future<File> downloadToFile(
    Uri uri,
    File target, {
    required void Function(int received, int? total) onProgress,
  }) async {
    _cancelRequested = false;
    final request = http.Request('GET', uri)..headers['User-Agent'] = _userAgent;

    http.StreamedResponse resp;
    try {
      resp = await _client.send(request).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw DownloadException('O servidor demorou demais para responder.');
    } on SocketException {
      throw DownloadException('Sem conexão com a internet.');
    }

    if (resp.statusCode != 200) {
      throw DownloadException('Não foi possível baixar (erro ${resp.statusCode}).');
    }
    final ct = resp.headers['content-type'] ?? '';
    if (ct.toLowerCase().startsWith('text/html')) {
      throw DownloadException(
          'Este endereço é uma página da web, não um arquivo de mídia. '
          'Abra o conteúdo no app oficial ou peça o arquivo original ao titular.');
    }

    final total = resp.contentLength;
    final partFile = File('${target.path}.part');
    final sink = partFile.openWrite();
    var received = 0;

    try {
      await for (final chunk in resp.stream) {
        if (_cancelRequested) throw DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      if (await partFile.exists()) await partFile.delete();
      if (e is DownloadCancelled) rethrow;
      if (e is DownloadException) rethrow;
      throw DownloadException('A conexão caiu durante o download. Tente novamente.');
    }

    if (total != null && total > 0 && received < total) {
      if (await partFile.exists()) await partFile.delete();
      throw DownloadException('O download ficou incompleto. Tente novamente.');
    }

    final finalTarget = await _uniqueFile(target);
    return partFile.rename(finalTarget.path);
  }

  /// Se "video.mp4" já existe, usa "video (2).mp4", "video (3).mp4"...
  static Future<File> _uniqueFile(File file) async {
    if (!await file.exists()) return file;
    final dir = file.parent.path;
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 2;
    while (true) {
      final candidate = File('$dir${Platform.pathSeparator}$base ($i)$ext');
      if (!await candidate.exists()) return candidate;
      i++;
    }
  }

  static String? _nameFromDisposition(String? header) {
    if (header == null) return null;
    final utf = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(header);
    if (utf != null) return Uri.decodeComponent(utf.group(1)!);
    final plain = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(header);
    return plain?.group(1);
  }

  void dispose() => _client.close();
}
