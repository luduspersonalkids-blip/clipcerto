// Testes da geração de legenda .srt e do texto com tempos.

import 'package:clipcerto/services/transcription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final result = TranscriptResult('Bom dia turma. Vamos aquecer.', [
    TranscriptSegment(0, 2.5, ' Bom dia turma.'),
    TranscriptSegment(2.5, 65.25, ' Vamos aquecer.'),
  ]);

  test('gera legenda .srt no formato correto', () {
    final srt = result.toSrt();
    expect(srt, contains('1\n00:00:00,000 --> 00:00:02,500\nBom dia turma.'));
    expect(srt, contains('2\n00:00:02,500 --> 00:01:05,250\nVamos aquecer.'));
  });

  test('texto com tempos', () {
    expect(result.toTimedText(), '[00:00] Bom dia turma.\n[00:02] Vamos aquecer.');
  });

  test('provedor padrão é a Groq', () {
    expect(TranscriptionProvider.byId(null).id, 'groq');
    expect(TranscriptionProvider.byId('openai').supportsSegments, isFalse);
  });
}
