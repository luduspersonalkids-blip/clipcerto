// Tela inicial: colar ou receber um link, ver a análise e agir.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_state.dart';
import '../services/download_service.dart';
import '../services/link_analyzer.dart';
import '../widgets/confirm_save_dialog.dart';
import '../widgets/platform_style.dart';
import '../widgets/progress_card.dart';

/// Recebe textos vindos do menu Compartilhar (preenchido pelo main.dart).
final ValueNotifier<String?> incomingSharedText = ValueNotifier<String?>(null);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  LinkAnalysis? _analysis;
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    incomingSharedText.addListener(_onShared);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShared());
  }

  @override
  void dispose() {
    incomingSharedText.removeListener(_onShared);
    _controller.dispose();
    super.dispose();
  }

  void _onShared() {
    final text = incomingSharedText.value;
    if (text == null || !mounted) return;
    incomingSharedText.value = null;
    _controller.text = text;
    _analyze();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _showSnack('A área de transferência está vazia. Copie um link primeiro.');
      return;
    }
    _controller.text = text;
    _analyze();
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    final result = LinkAnalyzer.analyze(_controller.text);
    setState(() {
      _analysis = result;
      _error = result == null ? 'Não encontrei um link válido. Cole um endereço que comece com https://' : null;
    });
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _analysis = null;
      _error = null;
    });
  }

  void _showSnack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _openExternal(Uri uri) async {
    final ok = await AppState.instance.openExternal(uri);
    if (!ok) _showSnack('Não foi possível abrir o link neste aparelho.');
  }

  /// Fluxo de salvamento para arquivo direto:
  /// 1) consulta tipo e tamanho; 2) confirmação; 3) download com progresso.
  Future<void> _checkAndSave(LinkAnalysis a) async {
    final state = AppState.instance;
    if (state.job?.isRunning ?? false) {
      _showSnack('Já existe um salvamento em andamento.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });

    ProbeResult probe;
    final service = DownloadService();
    try {
      probe = await service.probe(a.uri);
    } catch (e) {
      setState(() {
        _checking = false;
        _error = e.toString();
      });
      return;
    } finally {
      service.dispose();
    }
    setState(() => _checking = false);

    if (!probe.isMedia) {
      setState(() => _error =
          'Este endereço abre uma página (${probe.mimeType ?? 'tipo desconhecido'}), não um arquivo de mídia. '
          'O ClipCerto salva apenas arquivos de vídeo, áudio ou imagem acessíveis diretamente.');
      return;
    }

    // Garante que a pasta escolhida ainda está acessível.
    if (state.hasFolder && !await state.isFolderUsable()) {
      _showSnack('Perdi o acesso à pasta escolhida. Escolha a pasta novamente.');
      if (!await state.chooseFolder()) return;
    }
    if (!mounted) return;

    final name = await showConfirmSaveDialog(
      context,
      sourceLabel: a.uri.host,
      suggestedName: probe.suggestedName,
      sizeBytes: probe.sizeBytes,
    );
    if (name == null) return;

    try {
      final item = await state.save(
        uri: a.uri,
        fileName: name,
        platform: a.platformName,
        mimeHint: probe.mimeType,
      );
      if (!mounted) return;
      _showSnack(
        'Arquivo salvo: ${item.fileName}',
        action: SnackBarAction(label: 'Abrir', onPressed: () => state.openSaved(item)),
      );
    } catch (_) {
      // A mensagem de erro já aparece no cartão de progresso.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text('Cole ou compartilhe um link',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'O ClipCerto identifica a plataforma e mostra a forma permitida de guardar o conteúdo.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _analyze(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'https://...',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          onPressed: _clear,
                          icon: const Icon(Icons.clear_rounded),
                        ),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _paste,
                      icon: const Icon(Icons.content_paste_rounded),
                      label: const Text('Colar'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _controller.text.trim().isEmpty ? null : _analyze,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Analisar'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _MessageBox(text: _error!, isError: true),
              ],
              if (_analysis != null) ...[
                const SizedBox(height: 16),
                _AnalysisCard(
                  analysis: _analysis!,
                  checking: _checking,
                  onOpen: () => _openExternal(_analysis!.uri),
                  onSaveLink: () async {
                    await AppState.instance.addLink(_analysis!);
                    _showSnack('Link guardado na Biblioteca.');
                  },
                  onCheckAndSave: () => _checkAndSave(_analysis!),
                  onOpenStudio: () => _openExternal(Uri.parse('https://studio.youtube.com')),
                ),
              ],
              const ProgressCard(),
              if (_analysis == null && _error == null) ...[
                const SizedBox(height: 24),
                const _HowItWorks(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  final LinkAnalysis analysis;
  final bool checking;
  final VoidCallback onOpen;
  final VoidCallback onSaveLink;
  final VoidCallback onCheckAndSave;
  final VoidCallback onOpenStudio;

  const _AnalysisCard({
    required this.analysis,
    required this.checking,
    required this.onOpen,
    required this.onSaveLink,
    required this.onCheckAndSave,
    required this.onOpenStudio,
  });

  @override
  Widget build(BuildContext context) {
    final style = PlatformStyle.of(analysis.platform);
    final guidance = PlatformGuidance.of(analysis);
    final theme = Theme.of(context);
    final isSocial = guidance != null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: style.color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: style.color,
                  child: Icon(style.icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(analysis.platformName,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(analysis.kind),
                    ],
                  ),
                ),
                _StatusChip(direct: !isSocial),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              analysis.uri.toString(),
              maxLines: 2,
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            if (guidance != null) ...[
              Text(guidance.headline, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              for (var i = 0; i < guidance.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(guidance.steps[i])),
                    ],
                  ),
                ),
              if (guidance.ownerTip != null) ...[
                const SizedBox(height: 6),
                _MessageBox(text: guidance.ownerTip!, isError: false),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text('Abrir no ${analysis.platformName}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onSaveLink,
                    icon: const Icon(Icons.bookmark_add_rounded),
                    label: const Text('Guardar link'),
                  ),
                  if (analysis.platform == SourcePlatform.youtube)
                    OutlinedButton.icon(
                      onPressed: onOpenStudio,
                      icon: const Icon(Icons.video_settings_rounded),
                      label: const Text('Abrir YouTube Studio'),
                    ),
                ],
              ),
            ] else ...[
              Text(
                analysis.platform == SourcePlatform.directFile
                    ? 'Este endereço aponta para um arquivo. Antes de salvar, o app confere o tipo e o tamanho.'
                    : 'Endereço de outro site. O app verifica se é um arquivo de mídia; se for uma página comum, nada é baixado.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: checking ? null : onCheckAndSave,
                    icon: checking
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(checking ? 'Verificando...' : 'Verificar e salvar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onSaveLink,
                    icon: const Icon(Icons.bookmark_add_rounded),
                    label: const Text('Guardar link'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool direct;
  const _StatusChip({required this.direct});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(direct ? Icons.check_rounded : Icons.verified_user_rounded, size: 18),
      label: Text(direct ? 'Salvar direto' : 'Via app oficial'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MessageBox extends StatelessWidget {
  final String text;
  final bool isError;
  const _MessageBox({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.lightbulb_outline_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget item(IconData icon, String title, String text) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(text),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Como funciona', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        item(Icons.share_rounded, 'Compartilhe direto',
            'No YouTube, TikTok ou Instagram toque em Compartilhar e escolha ClipCerto.'),
        item(Icons.save_alt_rounded, 'Arquivos diretos',
            'Links que apontam para um arquivo de vídeo são salvos na pasta que você escolher.'),
        item(Icons.person_rounded, 'Seu Instagram',
            'Na aba Minha conta, salve seus próprios Reels, publicações e Stories pela API oficial.'),
        item(Icons.verified_user_rounded, 'Do jeito certo',
            'Nada de contornar proteções: quando a plataforma não libera, o app mostra o caminho oficial.'),
      ],
    );
  }
}
