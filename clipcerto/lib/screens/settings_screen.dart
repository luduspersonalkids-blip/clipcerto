// Ajustes: pasta de destino, conta do Instagram e regras de uso responsável.

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/native_bridge.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Ajustes', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_special_rounded),
                    title: const Text('Pasta de destino'),
                    subtitle: Text(state.destFolderLabel ??
                        'Nenhuma pasta escolhida. Ela será pedida no primeiro salvamento.'),
                    trailing: FilledButton.tonal(
                      onPressed: () => state.chooseFolder(),
                      child: Text(state.hasFolder ? 'Alterar' : 'Escolher'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    NativeBridge.isAndroid
                        ? 'Dica: crie uma pasta "ClipCerto" dentro de Movies ou Download pelo próprio seletor. '
                            'O Android guarda a permissão e o app usa a mesma pasta até você trocar.'
                        : 'Todos os próximos arquivos irão para esta pasta até você trocar.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.camera_alt_rounded),
                    title: const Text('Conta do Instagram'),
                    subtitle: Text(state.igToken == null ? 'Não conectada' : 'Conectada pela API oficial'),
                    trailing: state.igToken == null
                        ? null
                        : TextButton(
                            onPressed: () => state.setIgToken(null),
                            child: const Text('Desconectar'),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Uso responsável', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const _Rule('Salve apenas conteúdo seu ou com autorização do titular.'),
                const _Rule('O ClipCerto não contorna DRM, login, conteúdo privado ou bloqueios de download.'),
                const _Rule('YouTube, TikTok e Instagram são abertos nos apps oficiais, que oferecem seus próprios recursos de salvar.'),
                const _Rule('Ao repostar, dê crédito e respeite músicas, marcas e imagem de pessoas, especialmente de crianças.'),
                const SizedBox(height: 16),
                Center(child: Text('ClipCerto 1.0.0', style: theme.textTheme.bodySmall)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final String text;
  const _Rule(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
