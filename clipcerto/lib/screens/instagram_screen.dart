// Aba "Minha conta": conteúdo da SUA conta profissional do Instagram
// obtido pela API oficial da Meta. Nenhum conteúdo de terceiros é acessado.

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/instagram_service.dart';
import '../widgets/confirm_save_dialog.dart';
import '../widgets/progress_card.dart';

class InstagramScreen extends StatefulWidget {
  const InstagramScreen({super.key});

  @override
  State<InstagramScreen> createState() => _InstagramScreenState();
}

class _InstagramScreenState extends State<InstagramScreen> {
  final _tokenController = TextEditingController();
  bool _loading = false;
  String? _username;
  String? _error;
  String? _storiesError;
  List<IgMedia> _media = [];
  List<IgMedia> _stories = [];

  @override
  void initState() {
    super.initState();
    if (AppState.instance.igToken != null) _load();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await AppState.instance.setIgToken(_tokenController.text);
    _tokenController.clear();
    await _load();
  }

  Future<void> _load() async {
    final token = AppState.instance.igToken;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _storiesError = null;
    });
    final api = InstagramService(token);
    try {
      final name = await api.fetchUsername();
      final media = await api.fetchMyMedia();
      List<IgMedia> stories = [];
      String? storiesErr;
      try {
        stories = await api.fetchMyStories();
      } catch (e) {
        storiesErr = 'Stories indisponíveis pela API nesta configuração: $e';
      }
      if (!mounted) return;
      setState(() {
        _username = name;
        _media = media;
        _stories = stories;
        _storiesError = storiesErr;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      api.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disconnect() async {
    await AppState.instance.setIgToken(null);
    setState(() {
      _username = null;
      _media = [];
      _stories = [];
      _error = null;
    });
  }

  Future<void> _save(IgMedia m) async {
    final state = AppState.instance;
    if (state.job?.isRunning ?? false) return;
    final name = await showConfirmSaveDialog(
      context,
      sourceLabel: 'Instagram @${_username ?? ''}',
      suggestedName: m.suggestedFileName,
      rightsText: 'Confirmo que este conteúdo é da minha conta ou que tenho autorização de todos os envolvidos (música, imagem de pessoas, marcas).',
    );
    if (name == null || m.mediaUrl == null) return;
    try {
      await state.save(uri: Uri.parse(m.mediaUrl!), fileName: name, platform: 'Instagram');
    } catch (_) {
      // Erro exibido no cartão de progresso.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final connected = AppState.instance.igToken != null;
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: connected ? _connectedView(context) : _setupView(context),
            ),
          ),
        );
      },
    );
  }

  Widget _setupView(BuildContext context) {
    final theme = Theme.of(context);
    const steps = [
      'Sua conta do Instagram precisa ser Profissional (Criador de conteúdo ou Empresa). A troca é gratuita, em Configurações, Tipo de conta.',
      'Em developers.facebook.com crie um app, adicione o produto Instagram e escolha "API com login do Instagram".',
      'Em Funções do app, adicione sua conta do Instagram como Testadora e aceite o convite no Instagram.',
      'Na configuração da API, gere o token de acesso da sua conta e copie.',
      'Cole o token abaixo. Ele fica guardado apenas neste aparelho.',
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Salve o seu próprio Instagram',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Pela API oficial da Meta você acessa somente as mídias da sua conta profissional: Reels, '
          'publicações e Stories ativos. Não é possível acessar conteúdo de outras pessoas.',
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < steps.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(steps[i]),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Token de acesso do Instagram',
            prefixIcon: Icon(Icons.key_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _connect,
          icon: const Icon(Icons.link_rounded),
          label: const Text('Conectar minha conta'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 12),
        Text(
          'Custo: criar o app na Meta é gratuito. Para uso pessoal (você como testador) não é preciso '
          'enviar o app para revisão da Meta. O token expira e precisa ser renovado periodicamente.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _connectedView(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person_rounded)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_username == null ? 'Conectando...' : '@$_username',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(tooltip: 'Atualizar', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
              TextButton(onPressed: _disconnect, child: const Text('Desconectar')),
            ],
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            ),
          const ProgressCard(),
          const SizedBox(height: 12),
          Text('Stories ativos', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_storiesError != null)
            Text(_storiesError!, style: theme.textTheme.bodySmall)
          else if (_stories.isEmpty && !_loading)
            const Text('Nenhum Story ativo nas últimas 24 horas.')
          else
            _grid(_stories),
          const SizedBox(height: 20),
          Text('Reels e publicações', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_media.isEmpty && !_loading) const Text('Nenhuma mídia encontrada.') else _grid(_media),
        ],
      ),
    );
  }

  Widget _grid(List<IgMedia> items) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 4 : (c.maxWidth > 450 ? 3 : 2);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, i) => _MediaTile(
          media: items[i],
          onSave: () => _save(items[i]),
          onOpen: items[i].permalink == null
              ? null
              : () => AppState.instance.openExternal(Uri.parse(items[i].permalink!)),
        ),
      );
    });
  }
}

class _MediaTile extends StatelessWidget {
  final IgMedia media;
  final VoidCallback onSave;
  final VoidCallback? onOpen;
  const _MediaTile({required this.media, required this.onSave, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = media.previewUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (preview.isNotEmpty)
                  Image.network(
                    preview,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: scheme.surfaceContainerHighest),
                  )
                else
                  Container(
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.movie_rounded, size: 40),
                  ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(media.isStory
                        ? 'Story'
                        : (media.isVideo ? 'Vídeo' : (media.mediaType == 'CAROUSEL_ALBUM' ? 'Carrossel' : 'Foto'))),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: media.canSave ? onSave : null,
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: const Text('Salvar'),
                ),
              ),
              IconButton(
                tooltip: 'Abrir no Instagram',
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
