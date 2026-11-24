// Estado central do aplicativo (padrão simples com ChangeNotifier).
// Guarda: pasta de destino, histórico de arquivos salvos, links guardados,
// token do Instagram e o progresso do salvamento em andamento.
// As telas "escutam" este objeto e se redesenham quando algo muda.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/saved_item.dart';
import 'download_service.dart';
import 'link_analyzer.dart';
import 'native_bridge.dart';

enum SaveStatus { idle, downloading, finishing, done, error, cancelled }

class SaveJob {
  final String fileName;
  int received = 0;
  int? total;
  SaveStatus status;
  String? message;

  SaveJob({required this.fileName, this.status = SaveStatus.downloading});

  double? get fraction => (total != null && total! > 0) ? received / total! : null;
  bool get isRunning => status == SaveStatus.downloading || status == SaveStatus.finishing;
}

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  static const _kFolder = 'dest_folder';
  static const _kFolderLabel = 'dest_folder_label';
  static const _kHistory = 'history_v1';
  static const _kLinks = 'links_v1';
  static const _kIgToken = 'ig_token';

  late SharedPreferences _prefs;

  String? destFolder; // caminho (PC) ou content:// (Android)
  String? destFolderLabel; // texto amigável para mostrar na tela
  List<SavedItem> history = [];
  List<SavedLink> links = [];
  String? igToken;
  SaveJob? job;

  DownloadService? _downloader;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasFolder => destFolder != null;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    destFolder = _prefs.getString(_kFolder);
    destFolderLabel = _prefs.getString(_kFolderLabel);
    history = SavedItem.decodeList(_prefs.getString(_kHistory));
    links = SavedLink.decodeList(_prefs.getString(_kLinks));
    igToken = _prefs.getString(_kIgToken);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Pasta de destino
  // ---------------------------------------------------------------------------

  /// Abre o seletor de pasta do sistema. A pasta fica gravada para os próximos
  /// downloads até o usuário trocar.
  Future<bool> chooseFolder() async {
    if (NativeBridge.isAndroid) {
      final uri = await NativeBridge.pickFolder();
      if (uri == null) return false;
      destFolder = uri;
      destFolderLabel = await NativeBridge.describeFolder(uri);
    } else {
      final path = await getDirectoryPath(confirmButtonText: 'Usar esta pasta');
      if (path == null) return false;
      destFolder = path;
      destFolderLabel = path;
    }
    await _prefs.setString(_kFolder, destFolder!);
    await _prefs.setString(_kFolderLabel, destFolderLabel!);
    notifyListeners();
    return true;
  }

  /// Confere se a pasta salva ainda existe e se o app ainda pode gravar nela.
  Future<bool> isFolderUsable() async {
    final folder = destFolder;
    if (folder == null) return false;
    if (NativeBridge.isAndroid) return NativeBridge.hasFolderPermission(folder);
    return Directory(folder).exists();
  }

  // ---------------------------------------------------------------------------
  // Salvamento
  // ---------------------------------------------------------------------------

  /// Baixa e grava o arquivo na pasta escolhida.
  /// Só deve ser chamado DEPOIS da confirmação do usuário (tela de confirmação).
  Future<SavedItem> save({
    required Uri uri,
    required String fileName,
    required String platform,
    String? mimeHint,
  }) async {
    if (destFolder == null) {
      throw DownloadException('Escolha uma pasta de destino antes de salvar.');
    }
    final safeName = LinkAnalyzer.sanitizeFileName(fileName);
    job = SaveJob(fileName: safeName);
    notifyListeners();

    final dl = DownloadService();
    _downloader = dl;
    try {
      // Android: baixa para a pasta temporária do app e depois copia para a
      // pasta escolhida (via Storage Access Framework).
      // Computador: baixa direto na pasta escolhida.
      final File target;
      if (NativeBridge.isAndroid) {
        final tmp = await getTemporaryDirectory();
        target = File(p.join(tmp.path, safeName));
      } else {
        target = File(p.join(destFolder!, safeName));
      }

      final file = await dl.downloadToFile(uri, target, onProgress: (received, total) {
        job!
          ..received = received
          ..total = total;
        _notifyThrottled();
      });

      final size = await file.length();
      final mime = LinkAnalyzer.isMediaMime(mimeHint)
          ? mimeHint!.split(';').first.trim()
          : LinkAnalyzer.mimeForFileName(safeName);

      String location;
      String finalName = p.basename(file.path);
      if (NativeBridge.isAndroid) {
        job!.status = SaveStatus.finishing;
        notifyListeners();
        location = await NativeBridge.copyToFolder(
          treeUri: destFolder!,
          sourcePath: file.path,
          displayName: safeName,
          mimeType: mime,
        );
        finalName = safeName;
        await file.delete();
      } else {
        location = file.path;
      }

      final item = SavedItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        fileName: finalName,
        location: location,
        mimeType: mime,
        sourceUrl: uri.toString(),
        platform: platform,
        savedAt: DateTime.now(),
        sizeBytes: size,
      );
      history.insert(0, item);
      await _prefs.setString(_kHistory, SavedItem.encodeList(history));
      job!.status = SaveStatus.done;
      job!.message = 'Salvo em ${destFolderLabel ?? 'sua pasta'}';
      notifyListeners();
      return item;
    } on DownloadCancelled {
      job!
        ..status = SaveStatus.cancelled
        ..message = 'Salvamento cancelado. Nada foi gravado.';
      notifyListeners();
      rethrow;
    } catch (e) {
      job!
        ..status = SaveStatus.error
        ..message = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    } finally {
      dl.dispose();
      _downloader = null;
    }
  }

  void cancelSave() => _downloader?.cancel();

  void clearJob() {
    if (job?.isRunning ?? false) return;
    job = null;
    notifyListeners();
  }

  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds > 120) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Arquivos salvos: abrir, compartilhar, remover da lista
  // ---------------------------------------------------------------------------

  Future<void> openSaved(SavedItem item) async {
    if (NativeBridge.isAndroid) {
      await NativeBridge.openFile(item.location, item.mimeType);
      return;
    }
    final f = File(item.location);
    if (!await f.exists()) {
      throw Exception('O arquivo foi movido ou apagado da pasta.');
    }
    final ok = await launchUrl(Uri.file(item.location));
    if (!ok) throw Exception('Nenhum programa disponível para abrir este arquivo.');
  }

  /// Android: menu Compartilhar do sistema.
  /// Computador: abre a pasta com o arquivo selecionado (para arrastar, enviar etc.).
  Future<void> shareSaved(SavedItem item) async {
    if (NativeBridge.isAndroid) {
      await NativeBridge.shareFile(item.location, item.mimeType);
      return;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', item.location]);
    } else {
      await launchUrl(Uri.file(File(item.location).parent.path));
    }
  }

  Future<void> removeFromHistory(SavedItem item) async {
    history.removeWhere((e) => e.id == item.id);
    await _prefs.setString(_kHistory, SavedItem.encodeList(history));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Links guardados
  // ---------------------------------------------------------------------------

  Future<void> addLink(LinkAnalysis a) async {
    final url = a.uri.toString();
    links.removeWhere((l) => l.url == url);
    links.insert(0, SavedLink(url: url, platform: a.platformName, kind: a.kind, savedAt: DateTime.now()));
    await _prefs.setString(_kLinks, SavedLink.encodeList(links));
    notifyListeners();
  }

  Future<void> removeLink(SavedLink link) async {
    links.removeWhere((l) => l.url == link.url);
    await _prefs.setString(_kLinks, SavedLink.encodeList(links));
    notifyListeners();
  }

  /// Abre o link no app oficial (se instalado) ou no navegador.
  Future<bool> openExternal(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  // ---------------------------------------------------------------------------
  // Instagram (API oficial, conta própria)
  // ---------------------------------------------------------------------------

  Future<void> setIgToken(String? token) async {
    igToken = (token == null || token.trim().isEmpty) ? null : token.trim();
    if (igToken == null) {
      await _prefs.remove(_kIgToken);
    } else {
      await _prefs.setString(_kIgToken, igToken!);
    }
    notifyListeners();
  }
}

/// Formata bytes: 1536000 -> "1,5 MB".
String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '?';
  const units = ['B', 'KB', 'MB', 'GB'];
  double v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final txt = v >= 100 || i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${txt.replaceAll('.', ',')} ${units[i]}';
}
