// Ponte entre o Flutter (Dart) e o código nativo do Android (MainActivity.kt).
//
// Por que existe: algumas funções só o Android faz bem, de forma oficial:
//  - receber links pelo menu "Compartilhar";
//  - abrir o seletor de pastas do sistema (Storage Access Framework) e
//    guardar a permissão da pasta para os próximos downloads;
//  - gravar o arquivo na pasta escolhida, abrir e compartilhar o arquivo salvo.
//
// No computador essas funções não são usadas (o app usa file_selector e o
// sistema de arquivos comum).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('br.com.ludus.clipcerto/native');

  static final StreamController<String> _sharedTexts = StreamController<String>.broadcast();

  /// Emite um texto sempre que o usuário compartilha algo com o app já aberto.
  static Stream<String> get sharedTexts => _sharedTexts.stream;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Chamar uma vez ao iniciar o app.
  static void init() {
    if (!isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText' && call.arguments is String) {
        _sharedTexts.add(call.arguments as String);
      }
      return null;
    });
  }

  /// Texto recebido quando o app foi ABERTO a partir do "Compartilhar".
  static Future<String?> initialSharedText() async {
    if (!isAndroid) return null;
    return _channel.invokeMethod<String>('getInitialSharedText');
  }

  /// Abre o seletor de pastas do Android. Devolve o endereço da pasta (content://...)
  /// ou null se o usuário cancelar.
  static Future<String?> pickFolder() => _channel.invokeMethod<String>('pickFolder');

  /// Nome legível da pasta, ex.: "Movies/ClipCerto".
  static Future<String> describeFolder(String treeUri) async {
    final label = await _channel.invokeMethod<String>('describeFolder', {'treeUri': treeUri});
    return label ?? 'Pasta escolhida';
  }

  /// Confere se o app ainda tem permissão de escrita na pasta escolhida.
  static Future<bool> hasFolderPermission(String treeUri) async {
    final ok = await _channel.invokeMethod<bool>('hasFolderPermission', {'treeUri': treeUri});
    return ok ?? false;
  }

  /// Copia um arquivo temporário para a pasta escolhida. Devolve o content:// do novo arquivo.
  static Future<String> copyToFolder({
    required String treeUri,
    required String sourcePath,
    required String displayName,
    required String mimeType,
  }) async {
    final uri = await _channel.invokeMethod<String>('copyToFolder', {
      'treeUri': treeUri,
      'sourcePath': sourcePath,
      'displayName': displayName,
      'mimeType': mimeType,
    });
    if (uri == null) throw Exception('O Android não devolveu o arquivo salvo.');
    return uri;
  }

  static Future<void> openFile(String contentUri, String mimeType) =>
      _channel.invokeMethod('openUri', {'uri': contentUri, 'mimeType': mimeType});

  static Future<void> shareFile(String contentUri, String mimeType) =>
      _channel.invokeMethod('shareUri', {'uri': contentUri, 'mimeType': mimeType});
}
