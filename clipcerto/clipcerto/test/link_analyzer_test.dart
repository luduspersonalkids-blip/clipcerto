// Testes da análise de links. Rodar com: flutter test

import 'package:clipcerto/services/link_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractFirstUrl', () {
    test('extrai link de texto compartilhado pelo TikTok', () {
      const shared = 'Olha esse treino! https://vm.tiktok.com/ZMabc123/ #handebol';
      expect(LinkAnalyzer.extractFirstUrl(shared), 'https://vm.tiktok.com/ZMabc123/');
    });

    test('remove pontuação no final', () {
      expect(LinkAnalyzer.extractFirstUrl('veja https://youtu.be/abc.'), 'https://youtu.be/abc');
    });

    test('texto sem link devolve null', () {
      expect(LinkAnalyzer.extractFirstUrl('sem link aqui'), isNull);
    });
  });

  group('analyze', () {
    test('YouTube Short não é salvo direto', () {
      final a = LinkAnalyzer.analyze('https://www.youtube.com/shorts/xyz')!;
      expect(a.platform, SourcePlatform.youtube);
      expect(a.kind, 'Short');
      expect(a.canSaveDirectly, isFalse);
    });

    test('Instagram Reel e Story', () {
      expect(LinkAnalyzer.analyze('https://www.instagram.com/reel/C1/')!.kind, 'Reel');
      expect(LinkAnalyzer.analyze('https://instagram.com/stories/perfil/123/')!.kind, 'Story');
    });

    test('TikTok vídeo', () {
      final a = LinkAnalyzer.analyze('https://www.tiktok.com/@ludus/video/123')!;
      expect(a.platform, SourcePlatform.tiktok);
      expect(a.canSaveDirectly, isFalse);
    });

    test('arquivo .mp4 direto pode ser salvo', () {
      final a = LinkAnalyzer.analyze('https://meusite.com.br/videos/aula1.MP4')!;
      expect(a.platform, SourcePlatform.directFile);
      expect(a.canSaveDirectly, isTrue);
    });
  });

  group('nomes de arquivo', () {
    test('remove caracteres proibidos', () {
      expect(LinkAnalyzer.sanitizeFileName('aula: 1/2*?.mp4'), 'aula_ 1_2__.mp4');
    });

    test('sugere extensão pelo tipo', () {
      final name = LinkAnalyzer.suggestFileName(Uri.parse('https://x.com/download/abc'),
          contentType: 'video/mp4');
      expect(name, 'abc.mp4');
    });

    test('mime por extensão', () {
      expect(LinkAnalyzer.mimeForFileName('a.mov'), 'video/quicktime');
    });
  });
}
