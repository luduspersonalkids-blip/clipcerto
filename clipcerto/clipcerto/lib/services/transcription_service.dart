// Transcrição de áudio em texto por serviços de nuvem (Whisper).
//
// Provedores:
//  - Groq (padrão): modelo whisper-large-v3-turbo. Tem plano gratuito com limites
//    (arquivos de até 25 MB). Devolve trechos com tempo, o que permite gerar legenda .srt.
//  - OpenAI: modelo gpt-transcribe. Pago por uso. Devolve só o texto (sem legenda .srt).
//
// A chave de API é criada pelo usuário no site do provedor e colada nos Ajustes.
// O áudio é enviado ao provedor escolhido para ser transcrito.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class TranscriptSegment {
  final double start;
  final double end;
  final String text;
  TranscriptSegment(this.start, this.end, this.text);
}

class TranscriptResult {
  final String text;
  final List<TranscriptSegment> segments;
  TranscriptResult(this.text, this.segments);

  bool get hasTimestamps => segments.isNotEmpty;

  /// Legenda no formato .srt (para YouTube, editores de vídeo, CapCut etc.).
  String toSrt() {
    final b = StringBuffer();
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      b
        ..writeln(i + 1)
        ..writeln('${_srtTime(s.start)} --> ${_srtTime(s.end)}')
        ..writeln(s.text.trim())
        ..writeln();
    }
    return b.toString();
  }

  /// Texto com marcação de tempo [00:12] no início de cada trecho.
  String toTimedText() => segments.map((s) => '[${shortTime(s.start)}] ${s.text.trim()}').join('\n');

  static String _srtTime(double seconds) {
    final ms = (seconds * 1000).round();
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final r = ms % 1000;
    return '${_p(h)}:${_p(m)}:${_p(s)},${r.toString().padLeft(3, '0')}';
  }

  static String shortTime(double seconds) {
    final t = seconds.floor();
    final h = t ~/ 3600;
    final m = (t % 3600) ~/ 60;
    final s = t % 60;
    return h > 0 ? '$h:${_p(m)}:${_p(s)}' : '${_p(m)}:${_p(s)}';
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}

class TranscriptionProvider {
  final String id;
  final String label;
  final String baseUrl;
  final String model;
  final bool supportsSegments;
  final String keyUrl;
  final String costNote;

  const TranscriptionProvider({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.model,
    required this.supportsSegments,
    required this.keyUrl,
    required this.costNote,
  });

  static const groq = TranscriptionProvider(
    id: 'groq',
    label: 'Groq (recomendado)',
    baseUrl: 'https://api.groq.com/openai/v1',
    model: 'whisper-large-v3-turbo',
    supportsSegments: true,
    keyUrl: 'https://console.groq.com/keys',
    costNote: 'Plano gratuito com limite diário. No plano pago, cerca de US\$ 0,04 por hora de áudio.',
  );

  static const openai = TranscriptionProvider(
    id: 'openai',
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-transcribe',
    supportsSegments: false,
    keyUrl: 'https://platform.openai.com/api-keys',
    costNote: 'Pago por minuto de áudio; exige crédito na conta da OpenAI.',
  );

  static const all = [groq, openai];

  static TranscriptionProvider byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => groq);
}

class TranscriptionException implements Exception {
  final String message;
  TranscriptionException(this.message);
  @override
  String toString() => message;
}

class TranscriptionService {
  /// Limite de envio dos provedores (plano gratuito da Groq e OpenAI).
  static const maxBytes = 25 * 1024 * 1024;

  Future<TranscriptResult> transcribe({
    required File audio,
    required TranscriptionProvider provider,
    required String apiKey,
    String language = 'pt',
  }) async {
    final size = await audio.length();
    if (size > maxBytes) {
      throw TranscriptionException(
          'O áudio tem ${(size / 1024 / 1024).toStringAsFixed(1)} MB e o limite do serviço é 25 MB '
          '(cerca de 20 a 25 minutos de áudio). Corte o vídeo em partes menores e transcreva cada uma.');
    }

    final req = http.MultipartRequest('POST', Uri.parse('${provider.baseUrl}/audio/transcriptions'))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = provider.model
      ..fields['response_format'] = provider.supportsSegments ? 'verbose_json' : 'json'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    if (language != 'auto') req.fields['language'] = language;

    http.Response resp;
    try {
      final streamed = await req.send().timeout(const Duration(minutes: 6));
      resp = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw TranscriptionException('O serviço demorou demais. Tente novamente com um áudio menor.');
    } on SocketException {
      throw TranscriptionException('Sem conexão com a internet.');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw TranscriptionException('Resposta inesperada do serviço (${resp.statusCode}).');
    }

    if (resp.statusCode != 200) {
      final err = body['error'];
      final msg = err is Map ? (err['message'] ?? '').toString() : resp.body;
      if (resp.statusCode == 401) {
        throw TranscriptionException('Chave de API inválida. Confira a chave nos Ajustes.');
      }
      if (resp.statusCode == 429) {
        throw TranscriptionException(
            'Limite de uso atingido no provedor. Aguarde um pouco ou confira seu plano. Detalhe: $msg');
      }
      if (resp.statusCode == 413) {
        throw TranscriptionException('Arquivo grande demais para o serviço. Use um trecho menor.');
      }
      throw TranscriptionException('O serviço recusou a transcrição (${resp.statusCode}): $msg');
    }

    final text = (body['text'] as String?)?.trim() ?? '';
    final segs = <TranscriptSegment>[];
    final raw = body['segments'];
    if (raw is List) {
      for (final s in raw) {
        if (s is Map) {
          segs.add(TranscriptSegment(
            (s['start'] as num?)?.toDouble() ?? 0,
            (s['end'] as num?)?.toDouble() ?? 0,
            (s['text'] as String?) ?? '',
          ));
        }
      }
    }
    if (text.isEmpty && segs.isEmpty) {
      throw TranscriptionException('Nenhuma fala foi reconhecida neste áudio.');
    }
    return TranscriptResult(text, segs);
  }
}
