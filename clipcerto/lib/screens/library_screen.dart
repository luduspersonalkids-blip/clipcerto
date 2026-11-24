// Biblioteca: arquivos concluídos (abrir, compartilhar, remover da lista)
// e links guardados (abrir no app oficial, copiar, remover).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saved_item.dart';
import '../services/app_state.dart';
import '../services/native_bridge.dart';
import '../widgets/platform_style.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.video_library_rounded), text: 'Arquivos salvos'),
                Tab(icon: Icon(Icons.bookmarks_rounded), text: 'Links guardados'),
              ],
            ),
            const Expanded(
              child: TabBarView(children: [_FilesTab(), _LinksTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilesTab extends StatelessWidget {
  const _FilesTab();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final state = AppState.instance;
    final items = state.history;
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.video_file_rounded,
        text: 'Os arquivos que você salvar aparecem aqui.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = items[i];
        final style = PlatformStyle.byName(item.platform);
        final isVideo = item.mimeType.startsWith('video/');
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: style.color,
              child: Icon(isVideo ? Icons.movie_rounded : Icons.insert_drive_file_rounded,
                  color: Colors.white),
            ),
            title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${item.platform} · ${formatBytes(item.sizeBytes)} · ${_date(item.savedAt)}'),
            onTap: () => _run(context, () => state.openSaved(item)),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'open':
                    _run(context, () => state.openSaved(item));
                    break;
                  case 'share':
                    _run(context, () => state.shareSaved(item));
                    break;
                  case 'remove':
                    state.removeFromHistory(item);
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'open',
                    child: ListTile(leading: Icon(Icons.play_arrow_rounded), title: Text('Abrir'))),
                PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                        leading: const Icon(Icons.share_rounded),
                        title: Text(NativeBridge.isAndroid ? 'Compartilhar' : 'Mostrar na pasta'))),
                const PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                        leading: Icon(Icons.playlist_remove_rounded),
                        title: Text('Tirar da lista'),
                        subtitle: Text('O arquivo continua na pasta'))),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LinksTab extends StatelessWidget {
  const _LinksTab();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final state = AppState.instance;
    final links = state.links;
    if (links.isEmpty) {
      return const _EmptyState(
        icon: Icons.bookmark_border_rounded,
        text: 'Links guardados ficam aqui para você abrir depois no app oficial.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: links.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final SavedLink link = links[i];
        final style = PlatformStyle.byName(link.platform);
        return Card(
          child: ListTile(
            leading: CircleAvatar(backgroundColor: style.color, child: Icon(style.icon, color: Colors.white)),
            title: Text('${link.platform} · ${link.kind}'),
            subtitle: Text(link.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => state.openExternal(Uri.parse(link.url)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copiar link',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link.url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Link copiado.')));
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Remover',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => state.removeLink(link),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
