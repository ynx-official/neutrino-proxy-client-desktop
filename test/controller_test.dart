import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/application/controller.dart';
import 'package:neutrino_proxy_client_desktop/application/storage.dart';
import 'package:neutrino_proxy_client_desktop/core/config.dart';

import 'storage_test.dart' show MemoryVault;
import 'ui_test.dart' show FakeEngine;

void main() {
  test('repeated saves preserve pending credentials until reconnect', () async {
    final dir = await Directory.systemTemp.createTemp('neutrino-controller-');
    addTearDown(() => dir.delete(recursive: true));
    final engine = FakeEngine();
    addTearDown(engine.dispose);
    final config = ClientConfig(server: 'localhost');
    final store = ConfigStore(dir, MemoryVault());
    await store.save(config, const Secrets(license: 'first'));
    final controller = AppController(store: store, engine: engine);
    final container = ProviderContainer(
      overrides: [appProvider.overrideWith(() => controller)],
    );
    addTearDown(container.dispose);
    container.read(appProvider);
    await controller.initialize();
    engine.updates.add({
      'revision': 1,
      'state': 'connected',
      'activeConfig': config.toJson(),
    });
    await Future<void>.delayed(Duration.zero);
    expect(await controller.save(config, license: 'second'), isTrue);
    expect(container.read(appProvider).pending, isTrue);
    expect(await controller.save(config), isTrue);
    expect(container.read(appProvider).pending, isTrue);
    await controller.connect();
    engine.updates.add({
      'revision': 2,
      'state': 'connected',
      'activeConfig': config.toJson(),
    });
    await Future<void>.delayed(Duration.zero);
    expect(container.read(appProvider).pending, isFalse);
  });
}
