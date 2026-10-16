import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/application/controller.dart';
import 'package:neutrino_proxy_client_desktop/application/engine_bridge.dart';
import 'package:neutrino_proxy_client_desktop/application/storage.dart';
import 'package:neutrino_proxy_client_desktop/core/config.dart';
import 'package:neutrino_proxy_client_desktop/ui/app.dart';

import 'storage_test.dart' show MemoryVault;

class FakeEngine implements EnginePort {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  int connects = 0;
  @override
  Stream<Map<String, dynamic>> get events => updates.stream;
  @override
  Future<void> connect(ClientConfig config, Secrets secrets) async {
    connects++;
  }

  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() => updates.close();
}

void main() {
  testWidgets(
    'minimal layout, field validation and unsaved navigation protection',
    (tester) async {
      tester.view.physicalSize = const Size(860, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('neutrino-ui-'),
      ))!;
      addTearDown(
        () => tester.runAsync(() => directory.delete(recursive: true)),
      );
      final engine = FakeEngine();
      addTearDown(engine.dispose);
      final controller = AppController(
        store: ConfigStore(directory, MemoryVault()),
        engine: engine,
      );
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(() => controller)],
      );
      addTearDown(container.dispose);
      container.read(appProvider);
      await tester.runAsync(controller.initialize);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const NeutrinoApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未连接'), findsOneWidget);
      await tester.tap(find.text('填写连接信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();
      expect(find.text('请填写 License'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('server')), 'localhost');
      await tester.tap(find.byKey(const Key('nav-logs')));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('server')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
