import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/application/engine_bridge.dart';
import 'package:neutrino_proxy_client_desktop/core/config.dart';
import 'package:neutrino_proxy_client_desktop/core/protocol.dart';

void main() {
  test(
    'legacy isolate reports authentication and acknowledges shutdown',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      server.listen((s) {
        sockets.add(s);
        s.transform(frameTransformer).listen((frame) {
          if (frame.type == 2) {
            s.add(Frame(2, info: '{"code":0}').encode());
          }
        }, onError: (Object _) {});
      });
      final bridge = EngineBridge();
      await bridge.start([]);
      addTearDown(() async {
        await bridge.dispose();
        for (final s in sockets) {
          s.destroy();
        }
        await server.close();
      });
      final connected = bridge.events.firstWhere(
        (e) => e['state'] == 'connected',
      );
      await bridge.connect(
        ClientConfig(server: '127.0.0.1', port: server.port, ssl: false),
        const Secrets(license: 'test-license'),
      );
      await connected.timeout(const Duration(seconds: 5));
      final idle = bridge.events.firstWhere((e) => e['state'] == 'idle');
      await bridge.disconnect();
      await idle.timeout(const Duration(seconds: 5));
    },
  );
}
