import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/application/storage.dart';
import 'package:neutrino_proxy_client_desktop/background/ipc.dart';
import 'package:neutrino_proxy_client_desktop/background/service.dart';
import 'package:neutrino_proxy_client_desktop/core/config.dart';
import 'package:neutrino_proxy_client_desktop/core/protocol.dart';

import 'storage_test.dart' show MemoryVault;

void main() {
  test('IPC accepts fragmented and joined Unicode frames', () async {
    final bytes = [
      ...encodeMessage({'text': '连接'}),
      ...encodeMessage({'id': 2}),
    ];
    final messages = await Stream.fromIterable(bytes.map((b) => [b]))
        .transform(messageDecoder)
        .toList();
    expect(messages, [
      {'text': '连接'},
      {'id': 2},
    ]);
  });
  test('IPC rejects oversized, malformed and truncated input', () async {
    final oversized = ByteData(4)..setUint32(0, maxMessageBytes + 1);
    for (final bytes in [
      oversized.buffer.asUint8List(),
      [0, 0, 0, 1, 0xff],
      [0, 0, 0, 5, 123],
    ]) {
      await expectLater(
        Stream.value(bytes).transform(messageDecoder).toList(),
        throwsFormatException,
      );
    }
  });
  test('detaching state listeners preserves authenticated socket and latest snapshot', () async {
    final dir = await Directory.systemTemp.createTemp('neutrino-background-');
    final vault = MemoryVault();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    var closed = false;
    server.listen((socket) {
      sockets.add(socket);
      socket
          .transform(frameTransformer)
          .listen(
            (frame) {
              if (frame.type == 2) {
                socket.add(Frame(2, info: '{"code":0}').encode());
              }
            },
            onDone: () => closed = true,
            onError: (Object _) {},
          );
    });
    final config = ClientConfig(
      server: '127.0.0.1',
      port: server.port,
      ssl: false,
    );
    final store = ConfigStore(dir, vault);
    await store.save(config, const Secrets(license: 'synthetic-secret'));
    final service = ClientService(store: store);
    addTearDown(() async {
      await service.close();
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
      await dir.delete(recursive: true);
    });
    await service.initialize();
    final connected = service.events.firstWhere(
      (s) => (s['engine'] as Map)['state'] == 'connected',
    );
    await service.connect();
    final snapshot = await connected.timeout(const Duration(seconds: 5));
    final started = (snapshot['engine'] as Map)['connectedAt'];
    expect(jsonEncode(snapshot), isNot(contains('synthetic-secret')));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(closed, isFalse);
    expect((service.snapshot['engine'] as Map)['connectedAt'], started);
    await service.save(config, license: 'replacement-secret');
    expect(service.snapshot['pending'], isTrue);
    await service.save(config);
    expect(service.snapshot['pending'], isTrue);
    expect(service.snapshot['hasLicense'], isTrue);
    expect(closed, isFalse);
    await service.disconnect();
    expect((service.snapshot['engine'] as Map)['state'], 'idle');
  });
}
