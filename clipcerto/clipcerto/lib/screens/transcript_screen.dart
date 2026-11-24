// Mostra o texto transcrito e permite copiar, salvar (.txt e .srt) e compartilhar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_state.dart';
import '../services/native_bridge.dart';
import '../services/transcription_service.dart';

class TranscriptScreen extends StatefulWidget {
  final TranscriptResult result;
  final String baseName;
  const TranscriptScreen({super.key, required this.result, required this.baseName});

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  bool _showTimes = false;
  bool _saving = false;

  String get _currentText =>
      _showTimes && widget.result.hasTimestamps ? widget.result.toTimedText() : widget.result.text;

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _save(String content, String ext) async {
    final state = AppState.instance;
    if (!await state.ensureFolder()) return;
    setState(() => _saving = true);
    try {
      final item = await state.storeText(content, '${widget.baseName}.$ext');
      _snack('Salvo: ${item.fileName}',
          action: SnackBarAction(label: 'Abrir', onPressed: () => state.openSaved(item)));
    } catch (e) {
      _snack('Não foi possível salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final words = r.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcrição'),
        actions: [
          IconButton(
            tooltip: 'Copiar texto',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _currentText));
              _snack('Texto copiado.');
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Chip(label: Text('$words palavras')),
                    const Spacer(),
                    if (r.hasTimestamps)
                      FilterChip(
                        label: const Text('Mostrar tempos'),
                        selected: _showTimes,
                        onSelected: (v) => setState(() => _showTimes = v),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _currentText,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
              ),
              if (_saving) const LinearProgressIndicator(),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _save(_currentText, 'txt'),
                        icon: const Icon(Icons.description_rounded),
                        label: const Text('Salvar .txt'),
                      ),
                      if (r.hasTimestamps)
                        OutlinedButton.icon(
                          onPressed: _saving ? null : () => _save(r.toSrt(), 'srt'),
                          icon: const Icon(Icons.closed_caption_rounded),
                          label: const Text('Salvar legenda .srt'),
                        ),
                      if (NativeBridge.isAndroid)
                        OutlinedButton.icon(
                          onPressed: () => NativeBridge.shareText(_currentText),
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Compartilhar'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
