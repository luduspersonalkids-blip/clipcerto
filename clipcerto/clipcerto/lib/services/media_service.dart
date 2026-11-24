// Trabalha com vídeos e áudios que JÁ ESTÃO no aparelho:
//  - importar (seletor do sistema);
//  - separar o áudio do vídeo;
//  - preparar um áudio leve para transcrição.
//
// Android: usa o código nativo (MediaExtractor), sem programas extras.
// Windows: usa o ffmpeg.exe, que o GitHub coloca na mesma pasta do clipcerto.exe.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/local_media.dart';
import 'link_analyzer.dart';
import 'native_bridge.dart';

/// Mídia enviada para a aba Importar (pelo Compartilhar ou pela Biblioteca).
final ValueNotifier<LocalMedia?> pendingMedia = ValueNotifier<LocalMedia?>(null);

class MediaService {
  static const _extensions = [
    'mp4', 'mov', 'm4v', 'webm', 'mkv', '3gp',
    'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac',
  ];

  /// Abre o seletor de arquivos para escolher um vídeo ou áudio.
  static Future<LocalMedia?> pick() async {
    if (NativeBridge.isAndroid) {
      final m = await NativeBridge.pickMedia();
      return m == null ? null : LocalMedia.fromMap(m);
    }
    const group = XTypeGroup(label: 'Vídeos e áudios', extensions: _extensions);
    final f = await openFile(acceptedTypeGroups: [group], confirmButtonText: 'Importar');
    if (f == null) return null;
    final file = File(f.path);
    return LocalMedia(
      ref: f.path,
      name: p.basename(f.path),
      size: await file.length(),
      mime: LinkAnalyzer.mimeForFileName(f.path),
    );
  }

  /// Formatos de áudio disponíveis nesta plataforma.
  /// No celular o áudio é separado sem conversão (.m4a, mesma qualidade do vídeo).
  /// No computador o ffmpeg permite também .mp3.
  static List<String> get audioFormats => NativeBridge.isAndroid ? const ['m4a'] : const ['m4a', 'mp3'];

  /// Separa o áudio e devolve um arquivo temporário.
  static Future<File> extractAudio(LocalMedia m, {String format = 'm4a'}) async {
    if (NativeBridge.isAndroid) {
      final res = await NativeBridge.extractAudio(m.ref, '${_safe(m.baseName)}.m4a');
      return File(res['path'] as String);
    }
    final out = await _tempFile(format);
    final codec = format == 'mp3'
        ? ['-c:a', 'libmp3lame', '-q:a', '2']
        : ['-c:a', 'aac', '-b:a', '160k'];
    await _runFfmpeg(['-y', '-i', m.ref, '-vn', ...codec, out.path]);
    return out;
  }

  /// Prepara um áudio pequeno para enviar ao serviço de transcrição.
  static Future<File> audioForTranscription(LocalMedia m) async {
    if (NativeBridge.isAndroid) {
      if (m.isAudio) {
        final path = await NativeBridge.copyUriToCache(m.ref, _safe(m.name));
        return File(path);
      }
      return extractAudio(m);
    }
    // Computador: mono, 16 kHz, 48 kbps (o Whisper trabalha nesse padrão; arquivo ~0,4 MB por minuto).
    final out = await _tempFile('mp3');
    await _runFfmpeg([
      '-y', '-i', m.ref, '-vn', '-ac', '1', '-ar', '16000',
      '-c:a', 'libmp3lame', '-b:a', '48k', out.path,
    ]);
    return out;
  }

  static Future<File> _tempFile(String ext) async {
    final dir = await getTemporaryDirectory();
    return File(p.join(dir.path, 'clipcerto_${DateTime.now().millisecondsSinceEpoch}.$ext'));
  }

  static String? ffmpegPath() {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final exe = File(p.join(dir, Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg'));
    return exe.existsSync() ? exe.path : null;
  }

  static Future<void> _runFfmpeg(List<String> args) async {
    final exe = ffmpegPath();
    if (exe == null) {
      throw Exception('O arquivo ffmpeg.exe não está na pasta do ClipCerto. '
          'Baixe a versão Windows mais recente pelo GitHub (ela já vem com o ffmpeg).');
    }
    final r = await Process.run(exe, ['-hide_banner', '-loglevel', 'error', ...args]);
    if (r.exitCode != 0) {
      final err = r.stderr.toString().trim().split('\n').take(3).join(' ');
      if (err.contains('does not contain any stream') || err.contains('Output file #0 does not contain')) {
        throw Exception('Este arquivo não tem som.');
      }
      throw Exception('Não foi possível processar o arquivo. $err');
    }
  }

  static String _safe(String name) => LinkAnalyzer.sanitizeFileName(name);
}
