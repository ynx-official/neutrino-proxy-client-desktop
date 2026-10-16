import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'application/controller.dart';
import 'background/client.dart';
import 'platform/desktop.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final bridge = ProcessClientBackend(stdin, stdout);
  final container = ProviderContainer(
    overrides: [appProvider.overrideWith(() => AppController(backend: bridge))],
  );
  final key = GlobalKey<AppShellState>();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: NeutrinoApp(shellKey: key),
    ),
  );
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(860, 620),
      minimumSize: Size(860, 620),
      center: true,
      title: 'Neutrino',
      backgroundColor: Colors.white,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  await container.read(appProvider.notifier).initialize();
  await DesktopLifecycle(container, bridge, key).start();
}
