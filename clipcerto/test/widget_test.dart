// Teste simples de interface: a tela inicial abre e mostra os botões principais.

import 'package:clipcerto/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Tela inicial mostra Colar e Analisar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeScreen())));
    expect(find.text('Colar'), findsOneWidget);
    expect(find.text('Analisar'), findsOneWidget);
  });
}
