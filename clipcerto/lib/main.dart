// Ponto de entrada do ClipCerto.
// Monta o tema, a navegação (barra inferior no celular, trilho lateral no
// computador) e conecta o recebimento de links do menu Compartilhar.

import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/instagram_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_state.dart';
import 'services/native_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridge.init();
  await AppState.instance.load();
  runApp(const ClipCertoApp());
}

class ClipCertoApp extends StatelessWidget {
  const ClipCertoApp({super.key});

  static const _seed = Color(0xFF1B7F79); // verde-azulado: confiança e clareza

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        );
    return MaterialApp(
      title: 'ClipCerto',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  StreamSubscription<String>? _shareSub;

  static const _destinations = [
    (icon: Icons.add_link_rounded, label: 'Início'),
    (icon: Icons.video_library_rounded, label: 'Biblioteca'),
    (icon: Icons.person_rounded, label: 'Minha conta'),
    (icon: Icons.settings_rounded, label: 'Ajustes'),
  ];

  @override
  void initState() {
    super.initState();
    // Link recebido com o app fechado (aberto pelo Compartilhar).
    NativeBridge.initialSharedText().then(_receiveShared);
    // Link recebido com o app já aberto.
    _shareSub = NativeBridge.sharedTexts.listen(_receiveShared);
  }

  void _receiveShared(String? text) {
    if (text == null || text.trim().isEmpty) return;
    setState(() => _index = 0);
    incomingSharedText.value = text;
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  Widget _page() {
    switch (_index) {
      case 1:
        return const LibraryScreen();
      case 2:
        return const InstagramScreen();
      case 3:
        return const SettingsScreen();
      default:
        return const HomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;

    if (wide) {
      // Computador / tablet na horizontal: menu lateral.
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: _Logo(compact: true),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _page()),
          ],
        ),
      );
    }

    // Celular: barra inferior.
    return Scaffold(
      appBar: AppBar(title: const _Logo(), centerTitle: true),
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations) NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final bool compact;
  const _Logo({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.check_rounded, color: scheme.onPrimary, size: 20),
        ),
        if (!compact) const SizedBox(width: 8),
        if (!compact)
          Text('ClipCerto',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
      ],
    );
  }
}
