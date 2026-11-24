// Cores, ícones e textos de orientação de cada plataforma.
// As orientações descrevem SOMENTE caminhos oficiais oferecidos pelas plataformas.

import 'package:flutter/material.dart';

import '../services/link_analyzer.dart';

class PlatformStyle {
  final Color color;
  final IconData icon;
  const PlatformStyle(this.color, this.icon);

  static PlatformStyle of(SourcePlatform p) {
    switch (p) {
      case SourcePlatform.youtube:
        return const PlatformStyle(Color(0xFFE53935), Icons.smart_display_rounded);
      case SourcePlatform.tiktok:
        return const PlatformStyle(Color(0xFF111111), Icons.music_note_rounded);
      case SourcePlatform.instagram:
        return const PlatformStyle(Color(0xFFC13584), Icons.camera_alt_rounded);
      case SourcePlatform.directFile:
        return const PlatformStyle(Color(0xFF1B7F79), Icons.movie_rounded);
      case SourcePlatform.webPage:
        return const PlatformStyle(Color(0xFF546E7A), Icons.public_rounded);
    }
  }

  static PlatformStyle byName(String name) {
    switch (name) {
      case 'YouTube':
        return of(SourcePlatform.youtube);
      case 'TikTok':
        return of(SourcePlatform.tiktok);
      case 'Instagram':
        return of(SourcePlatform.instagram);
      case 'Arquivo direto':
        return of(SourcePlatform.directFile);
      default:
        return of(SourcePlatform.webPage);
    }
  }
}

/// Passos oficiais exibidos para cada plataforma.
class PlatformGuidance {
  final String headline;
  final List<String> steps;
  final String? ownerTip;
  const PlatformGuidance({required this.headline, required this.steps, this.ownerTip});

  static PlatformGuidance? of(LinkAnalysis a) {
    switch (a.platform) {
      case SourcePlatform.youtube:
        return const PlatformGuidance(
          headline:
              'O YouTube não libera o arquivo de vídeo para aplicativos de terceiros. O ClipCerto abre o vídeo no app oficial e mostra os caminhos permitidos.',
          steps: [
            'Para assistir sem internet: use o botão Download do próprio app do YouTube (recurso do YouTube Premium; o vídeo fica disponível dentro do app).',
            'Para ter o arquivo: peça o original ao criador ou verifique se ele disponibiliza o arquivo em outro lugar.',
          ],
          ownerTip:
              'O vídeo é seu? Entre no YouTube Studio pelo computador, abra Conteúdo, clique nos três pontos do vídeo e escolha Baixar. Depois use o ClipCerto para organizar o arquivo.',
        );
      case SourcePlatform.tiktok:
        return const PlatformGuidance(
          headline:
              'O TikTok só permite salvar pelo próprio app, e apenas quando o criador deixou os downloads liberados.',
          steps: [
            'Toque em Abrir no TikTok.',
            'No vídeo, toque em Compartilhar e depois em Salvar vídeo.',
            'Se a opção não aparecer, o criador desativou os downloads: respeite a escolha e, se precisar, peça o arquivo a ele.',
          ],
          ownerTip:
              'Vídeo seu: a mesma opção Salvar vídeo funciona no seu perfil. Para todos de uma vez, use Configurações e privacidade, Conta, Baixar seus dados.',
        );
      case SourcePlatform.instagram:
        final isStory = a.kind == 'Story';
        return PlatformGuidance(
          headline: isStory
              ? 'Stories de outras pessoas não podem ser salvos por aplicativos de terceiros. Os seus podem, pela API oficial (aba Minha conta) ou pelo seu Arquivo no Instagram.'
              : 'O Instagram não libera Reels e publicações de outras pessoas para aplicativos de terceiros.',
          steps: isStory
              ? const [
                  'Story seu e ainda ativo (até 24 horas): use a aba Minha conta do ClipCerto.',
                  'Story seu já expirado: no Instagram, abra Perfil, Menu, Arquivo, escolha o Story e use Mais, Salvar.',
                  'Story de outra pessoa: peça o arquivo diretamente ao titular.',
                ]
              : const [
                  'Toque em Abrir no Instagram. Em alguns Reels públicos o próprio Instagram oferece Baixar no menu de compartilhar, quando o criador permite.',
                  'Use Salvar (marcador) para guardar na sua coleção dentro do Instagram.',
                  'Precisa do arquivo de outra pessoa? Peça o original ao criador.',
                ],
          ownerTip:
              'Conteúdo seu: conecte sua conta profissional na aba Minha conta, ou baixe tudo em Central de Contas, Suas informações e permissões, Baixar suas informações.',
        );
      case SourcePlatform.directFile:
      case SourcePlatform.webPage:
        return null;
    }
  }
}
