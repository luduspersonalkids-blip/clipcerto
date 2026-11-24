// Cartão que mostra o andamento do salvamento atual:
// barra de progresso, bytes recebidos, botão Cancelar e mensagens de
// sucesso ou erro.

import 'package:flutter/material.dart';

import '../services/app_state.dart';

class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final job = state.job;
        if (job == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;

        Color bg;
        IconData icon;
        String title;
        switch (job.status) {
          case SaveStatus.downloading:
            bg = scheme.secondaryContainer;
            icon = Icons.downloading_rounded;
            title = 'Baixando...';
            break;
          case SaveStatus.finishing:
            bg = scheme.secondaryContainer;
            icon = Icons.drive_file_move_rounded;
            title = 'Gravando na pasta escolhida...';
            break;
          case SaveStatus.done:
            bg = scheme.primaryContainer;
            icon = Icons.check_circle_rounded;
            title = 'Pronto!';
            break;
          case SaveStatus.cancelled:
            bg = scheme.surfaceContainerHighest;
            icon = Icons.cancel_rounded;
            title = 'Cancelado';
            break;
          case SaveStatus.error:
            bg = scheme.errorContainer;
            icon = Icons.error_rounded;
            title = 'Não foi possível salvar';
            break;
          case SaveStatus.idle:
            return const SizedBox.shrink();
        }

        final pct = job.fraction;
        final progressText = job.status == SaveStatus.downloading
            ? (pct != null
                ? '${formatBytes(job.received)} de ${formatBytes(job.total)} (${(pct * 100).toStringAsFixed(0)}%)'
                : '${formatBytes(job.received)} recebidos')
            : (job.message ?? '');

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (job.isRunning)
                    TextButton.icon(
                      onPressed: state.cancelSave,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancelar'),
                    )
                  else
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: state.clearJob,
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(job.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (job.isRunning) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: job.status == SaveStatus.finishing ? null : pct,
                    minHeight: 10,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(progressText),
            ],
          ),
        );
      },
    );
  }
}
