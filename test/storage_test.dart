import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/application/storage.dart';
import 'package:neutrino_proxy_client_desktop/core/config.dart';

class MemoryVault implements CredentialVault {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (fail) {
      throw StateError('unavailable');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test(
    'custom certificate survives loss of the selected external file',
    () async {
      final dir = await Directory.systemTemp.createTemp('neutrino-cert-');
      addTearDown(() => dir.delete(recursive: true));
      final external = File('${dir.path}/selected.pem');
      final bytes = await File('test/fixtures/tls/server.pem').readAsBytes();
      await external.writeAsBytes(bytes);
      final store = ConfigStore(Directory('${dir.path}/app'), MemoryVault());
      await store.save(
        ClientConfig(certificatePath: external.path),
        const Secrets(),
      );
      await external.delete();
      final restored = await store.load();
      expect(restored.config.certificatePath, isNot(external.path));
      expect(await File(restored.config.certificatePath).readAsBytes(), bytes);
    },
  );
  test('config contains reference only and preserves stable identity across restarts', () async {
    final dir = await Directory.systemTemp.createTemp('neutrino-storage-');
    addTearDown(() => dir.delete(recursive: true));
    final vault = MemoryVault();
    final store = ConfigStore(dir, vault);
    final first = await store.load();
    await store.save(
      first.config.copyWith({'server': 'localhost'}),
      const Secrets(
        license: 'secret-fixture',
        storePassword: 'password-fixture',
      ),
    );
    final file = await File('${dir.path}/config.json').readAsString();
    expect(file, isNot(contains('secret-fixture')));
    expect(file, isNot(contains('password-fixture')));
    expect(jsonDecode(file)['credentialId'], isNotEmpty);
    final restored = await ConfigStore(dir, vault).load();
    expect(restored.config.clientId, first.config.clientId);
    expect(restored.secrets.license, 'secret-fixture');
    vault.fail = true;
    await expectLater(
      store.save(
        restored.config.copyWith({'server': 'changed'}),
        const Secrets(license: 'new'),
      ),
      throwsStateError,
    );
    expect(await File('${dir.path}/config.json').readAsString(), file);
  });
}
