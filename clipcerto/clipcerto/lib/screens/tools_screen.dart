// Aba "Importar": trabalha com um vídeo ou áudio que já está no aparelho.
// Opções: salvar cópia do vídeo, extrair o áudio e transcrever.

import 'package:flutter/material.dart';

import '../models/local_media.dart';
import '../services/app_state.dart';
import '../services/media_service.dart';
import '../services/native_bridge.dart';
import '../services/transcription_service.dart';
import '../widgets/confirm_save_dialog.dart';
import 'transcript_screen.dart';

class ToolsScreen extends StatefulWidget {
  /// Chamado para levar o usuário à aba Ajustes (configurar a transcrição).
  final VoidCallback onOpenSettings;
  const ToolsScreen({super.key, required this.onOpenSettings});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  LocalMedia? _media;
  String? _busy; // texto do que está acontecendo agora
  String? _error;
  String _audioFormat = 'm4a';

  @override
  void initState() {
    super.initState();
    pendingMedia.addListener(_takePending);
    WidgetsBinding.instance.addPostFrameCallback((_) => _takePending());
  }

  @override
  void dispose() {
    pendingMedia.removeListener(_takePending);
    super.dispose();
  }

  void _takePending() {
    final m = pendingMedia.value;
    if (m == null || !mounted) return;
    pendingMedia.value = null;
    setState(() {
      _media = m;
      _error = null;
    });
  }

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _run(String label, Future<void> Function() job) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pick() async {
    try {
      final m = await MediaService.pick();
      if (m != null) {
        setState(() {
          _media = m;
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  // ------------------------------------------------------------- Salvar vídeo
  Future<void> _saveCopy() async {
    final m = _media!;
    final state = AppState.instance;
    if (!await state.ensureFolder()) return;
    if (!mounted) return;
    final name = await showConfirmSaveDialog(
      context,
      sourceLabel: 'Arquivo do aparelho',
      suggestedName: m.name,
      sizeBytes: m.size > 0 ? m.size : null,
      rightsText: 'Confirmo que tenho direito ou autorização para guardar e usar este conteúdo.',
    );
    if (name == null) return;
    await _run('Copiando para a pasta...', () async {
      final item = await state.storeLocalCopy(m, name);
      _snack('Salvo: ${item.fileName}',
          action: SnackBarAction(label: 'Abrir', onPressed: () => state.openSaved(item)));
    });
  }

  // ------------------------------------------------------------- Extrair áudio
  Future<void> _extractAudio() async {
    final m = _media!;
    final state = AppState.instance;
    if (!await state.ensureFolder()) return;
    if (!mounted) return;
    final name = await showConfirmSaveDialog(
      context,
      sourceLabel: m.name,
      suggestedName: '${m.baseName}.$_audioFormat',
      rightsText: 'Confirmo que tenho direito ou autorização para usar o áudio deste conteúdo.',
    );
    if (name == null) return;
    await _run('Separando o áudio...', () async {
      final tmp = await MediaService.extractAudio(m, format: _audioFormat);
      final item = await state.storeTempFile(
        tmp,
        fileName: name,
        mime: _audioFormat == 'mp3' ? 'audio/mpeg' : 'audio/mp4',
        platform: 'Áudio',
        source: m.name,
      );
      _snack('Áudio salvo: ${item.fileName}',
          action: SnackBarAction(label: 'Ouvir', onPressed: () => state.openSaved(item)));
    });
  }

  // ------------------------------------------------------------- Transcrever
  Future<void> _transcribe() async {
    final m = _media!;
    final state = AppState.instance;
    final provider = TranscriptionProvider.byId(state.trProviderId);
    final key = state.trKey;
    if (key == null) {
      _snack('Configure a chave de transcrição nos Ajustes.',
          action: SnackBarAction(label: 'Ajustes', onPressed: widget.onOpenSettings));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.subtitles_rounded, size: 36),
        title: const Text('Transcrever'),
        content: Text(
          'O áudio de "${m.name}" será enviado para ${provider.label.replaceAll(' (recomendado)', '')} '
          'para ser convertido em texto.\n\n'
          'Use apenas com conteúdo seu ou com autorização, e evite gravações com dados pessoais de terceiros '
          '(por exemplo, alunos identificados) sem consentimento.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Transcrever')),
        ],
      ),
    );
    if (ok != true) return;

    await _run('Preparando o áudio...', () async {
      final audio = await MediaService.audioForTranscription(m);
      if (mounted) setState(() => _busy = 'Transcrevendo... (vídeos longos podem levar alguns minutos)');
      try {
        final result = await TranscriptionService().transcribe(
          audio: audio,
          provider: provider,
          apiKey: key,
          language: state.trLanguage,
        );
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TranscriptScreen(result: result, baseName: m.baseName),
        ));
      } finally {
        if (await audio.exists()) await audio.delete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = _media;
    final busy = _busy != null;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text('Importar vídeo ou áudio',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                NativeBridge.isAndroid
                    ? 'Escolha um arquivo do celular ou, na galeria, toque em Compartilhar e escolha ClipCerto.'
                    : 'Escolha um vídeo ou áudio do computador.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: busy ? null : _pick,
                icon: const Icon(Icons.video_library_rounded),
                label: Text(m == null ? 'Escolher vídeo ou áudio' : 'Escolher outro arquivo'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              if (m != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(m.isAudio ? Icons.audiotrack_rounded : Icons.movie_rounded),
                    ),
                    title: Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${m.isAudio ? 'Áudio' : 'Vídeo'} · ${formatBytes(m.size)}'),
                  ),
                ),
                const SizedBox(height: 8),
                if (m.isVideo)
                  _ActionCard(
                    icon: Icons.save_alt_rounded,
                    title: 'Salvar vídeo',
                    text: 'Guarda uma cópia na pasta do ClipCerto, com o nome que você escolher.',
                    button: 'Salvar vídeo',
                    onPressed: busy ? null : _saveCopy,
                  ),
                if (m.isVideo)
                  _ActionCard(
                    icon: Icons.music_note_rounded,
                    title: 'Extrair áudio',
                    text: NativeBridge.isAndroid
                        ? 'Separa o som do vídeo em .m4a, sem perder qualidade. Toca em qualquer celular e computador.'
                        : 'Separa o som do vídeo em .m4a ou .mp3.',
                    button: 'Extrair áudio',
                    onPressed: busy ? null : _extractAudio,
                    extra: MediaService.audioFormats.length > 1
                        ? SegmentedButton<String>(
                            segments: [
                              for (final f in MediaService.audioFormats)
                                ButtonSegment(value: f, label: Text('.$f')),
                            ],
                            selected: {_audioFormat},
                            onSelectionChanged: (s) => setState(() => _audioFormat = s.first),
                          )
                        : null,
                  ),
                ListenableBuilder(
                  listenable: AppState.instance,
                  builder: (context, _) {
                    final state = AppState.instance;
                    final provider = TranscriptionProvider.byId(state.trProviderId);
                    final configured = state.trKey != null;
                    return _ActionCard(
                      icon: Icons.subtitles_rounded,
                      title: 'Transcrever',
                      text: configured
                          ? 'Converte a fala em texto${provider.supportsSegments ? ' e legenda .srt' : ''} '
                              'usando ${provider.label.replaceAll(' (recomendado)', '')}. Limite: cerca de 20 minutos por arquivo.'
                          : 'Converte a fala em texto. Para ativar, crie uma chave gratuita e cole nos Ajustes.',
                      button: configured ? 'Transcrever' : 'Configurar',
                      onPressed: busy ? null : (configured ? _transcribe : widget.onOpenSettings),
                    );
                  },
                ),
              ],
              if (busy) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_busy!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(minHeight: 8),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!)),
                    ],
                  ),
                ),
              ],
              if (m == null) ...[
                const SizedBox(height: 24),
                Text('Como conseguir o vídeo do jeito certo',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const _Tip(icon: Icons.music_note_rounded, text: 'TikTok: Compartilhar, Salvar vídeo (quando o criador permite). O vídeo vai para a galeria.'),
                const _Tip(icon: Icons.camera_alt_rounded, text: 'Instagram: Baixar no menu de compartilhar (quando permitido) ou seus conteúdos pela aba Minha conta.'),
                const _Tip(icon: Icons.smart_display_rounded, text: 'YouTube: seus vídeos pelo YouTube Studio. De outras pessoas, peça o arquivo ao criador.'),
                const _Tip(icon: Icons.videocam_rounded, text: 'Gravações suas (aulas, treinos, reuniões) funcionam direto da galeria.'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String button;
  final VoidCallback? onPressed;
  final Widget? extra;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.button,
    required this.onPressed,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(text),
            if (extra != null) ...[const SizedBox(height: 10), extra!],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(onPressed: onPressed, child: Text(button)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(text),
    );
  }
}
