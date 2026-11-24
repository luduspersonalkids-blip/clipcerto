// Ajustes: pasta de destino, conta do Instagram e regras de uso responsável.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_state.dart';
import '../services/native_bridge.dart';
import '../services/transcription_service.dart';

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
                const _TranscriptionSettings(),
                const SizedBox(height: 16),
                Text('Uso responsável', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const _Rule('Salve apenas conteúdo seu ou com autorização do titular.'),
                const _Rule('O ClipCerto não contorna DRM, login, conteúdo privado ou bloqueios de download.'),
                const _Rule('YouTube, TikTok e Instagram são abertos nos apps oficiais, que oferecem seus próprios recursos de salvar.'),
                const _Rule('Ao repostar, dê crédito e respeite músicas, marcas e imagem de pessoas, especialmente de crianças.'),
                const SizedBox(height: 16),
                Center(child: Text('ClipCerto 2.0.0', style: theme.textTheme.bodySmall)),
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


/// Configuração da transcrição: provedor, idioma e chave de API.
class _TranscriptionSettings extends StatelessWidget {
  const _TranscriptionSettings();

  Future<void> _editKey(BuildContext context, TranscriptionProvider p) async {
    final state = AppState.instance;
    final controller = TextEditingController(text: state.trKeyFor(p.id) ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Chave de API: ${p.label.replaceAll(' (recomendado)', '')}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Crie a chave em ${p.keyUrl}, copie e cole abaixo. Ela fica guardada só neste aparelho.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Chave de API',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: p.keyUrl));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Endereço copiado.')));
              }
            },
            child: const Text('Copiar endereço'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Salvar')),
        ],
      ),
    );
    controller.dispose();
    if (saved != null) await state.setTrKey(p.id, saved);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    final state = AppState.instance;
    final theme = Theme.of(context);
    final provider = TranscriptionProvider.byId(state.trProviderId);
    final hasKey = state.trKey != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transcrição', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: provider.id,
                  decoration: const InputDecoration(labelText: 'Serviço', border: OutlineInputBorder()),
                  items: [
                    for (final p in TranscriptionProvider.all)
                      DropdownMenuItem(value: p.id, child: Text(p.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) state.setTrProvider(v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: state.trLanguage,
                  decoration: const InputDecoration(labelText: 'Idioma do áudio', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'pt', child: Text('Português')),
                    DropdownMenuItem(value: 'es', child: Text('Espanhol')),
                    DropdownMenuItem(value: 'en', child: Text('Inglês')),
                    DropdownMenuItem(value: 'auto', child: Text('Detectar automaticamente')),
                  ],
                  onChanged: (v) {
                    if (v != null) state.setTrLanguage(v);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(hasKey ? Icons.check_circle_rounded : Icons.key_off_rounded,
                      color: hasKey ? theme.colorScheme.primary : theme.colorScheme.error),
                  title: Text(hasKey ? 'Chave configurada' : 'Chave não configurada'),
                  subtitle: Text(provider.costNote),
                  trailing: FilledButton.tonal(
                    onPressed: () => _editKey(context, provider),
                    child: Text(hasKey ? 'Trocar' : 'Configurar'),
                  ),
                ),
                if (hasKey)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => state.setTrKey(provider.id, null),
                      child: const Text('Remover chave'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'Como criar a chave grátis da Groq: entre em console.groq.com com sua conta Google, '
            'abra API Keys, toque em Create API Key, copie e cole aqui.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
