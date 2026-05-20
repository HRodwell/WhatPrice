import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'database.dart';
import 'screens/home_screen.dart';
import 'sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = await AppDatabase.open();
    final state = AppState(db);
    await state.load();
    final sync = SyncService(state);
    await sync.loadStatus();
    runApp(WhatPriceApp(state: state, sync: sync));
  } catch (e, st) {
    runApp(_StartupErrorApp(error: e, stack: st));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.stack});
  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('WhatPrice failed to start')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Something went wrong while opening the database.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    error.toString(),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    stack.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WhatPriceApp extends StatelessWidget {
  const WhatPriceApp({super.key, required this.state, required this.sync});
  final AppState state;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB8722C),
      brightness: Brightness.light,
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: sync),
      ],
      child: MaterialApp(
        title: 'WhatPrice',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: scheme,
          useMaterial3: true,
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
