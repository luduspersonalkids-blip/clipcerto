// Janela de confirmação exibida ANTES de qualquer salvamento.
// O usuário revisa: origem, nome do arquivo, pasta de destino e confirma
// que tem direito ou autorização para salvar o conteúdo.
// Devolve o nome final do arquivo, ou null se o usuário cancelar.

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/link_analyzer.dart';

Future<String?> showConfirmSaveDialog(
  BuildContext context, {
  required String sourceLabel,
  required String suggestedName,
  int? sizeBytes,
  String rightsText = 'Confirmo que tenho direito ou autorização do titular para salvar este conteúdo.',
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConfirmSaveDialog(
      sourceLabel: sourceLabel,
      suggestedName: suggestedName,
      sizeBytes: sizeBytes,
      rightsText: rightsText,
    ),
  );
}

class _ConfirmSaveDialog extends StatefulWidget {
  final String sourceLabel;
  final String suggestedName;
  final int? sizeBytes;
  final String rightsText;

  const _ConfirmSaveDialog({
    required this.sourceLabel,
    required this.suggestedName,
    required this.sizeBytes,
    required this.rightsText,
  });

  @override
  State<_ConfirmSaveDialog> createState() => _ConfirmSaveDialogState();
}

class _ConfirmSaveDialogState extends State<_ConfirmSaveDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.suggestedName);
  bool _rightsConfirmed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final canSave = _rightsConfirmed && state.hasFolder && _name.text.trim().isNotEmpty;
        return AlertDialog(
          icon: const Icon(Icons.download_for_offline_rounded, size: 36),
          title: const Text('Confirmar salvamento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(icon: Icons.link_rounded, label: 'Origem', value: widget.sourceLabel),
                if (widget.sizeBytes != null)
                  _InfoRow(
                    icon: Icons.sd_storage_rounded,
                    label: 'Tamanho',
                    value: formatBytes(widget.sizeBytes),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nome do arquivo',
                    prefixIcon: Icon(Icons.edit_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(state.hasFolder ? 'Pasta de destino' : 'Nenhuma pasta escolhida'),
                    subtitle: Text(
                      state.destFolderLabel ?? 'Toque em Escolher para definir onde salvar',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () => state.chooseFolder(),
                      child: Text(state.hasFolder ? 'Alterar' : 'Escolher'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _rightsConfirmed,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(widget.rightsText, style: theme.textTheme.bodyMedium),
                  onChanged: (v) => setState(() => _rightsConfirmed = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: canSave
                  ? () => Navigator.pop(context, LinkAnalyzer.sanitizeFileName(_name.text))
                  : null,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, maxLines: 3, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
