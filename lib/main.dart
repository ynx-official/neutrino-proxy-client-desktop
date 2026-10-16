import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'application/controller.dart';
import 'application/engine_bridge.dart';
import 'application/storage.dart';
import 'platform/desktop.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final bridge = EngineBridge();
  await bridge.start(
    (await rootBundle.load('assets/test.jks')).buffer.asUint8List(),
  );
  final store = ConfigStore(
    Directory('${directory.path}/neutrino-flutter'),
    const SystemVault(),
  );
  final container = ProviderContainer(
    overrides: [
      appProvider.overrideWith(
        () => AppController(store: store, engine: bridge),
      ),
    ],
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
