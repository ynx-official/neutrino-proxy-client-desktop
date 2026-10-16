import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/core/config.dart';
import 'package:neutrino_proxy_client_desktop/core/engine.dart';
import 'package:neutrino_proxy_client_desktop/core/protocol.dart';

import 'engine_test.dart' show until;

void main() {
  for (final hostname in ['localhost', '127.0.0.1']) {
    test(
      'TLS validates the trusted certificate and hostname: $hostname',
      () async {
        final context = SecurityContext()
          ..useCertificateChain('test/fixtures/tls/server.pem')
          ..usePrivateKey('test/fixtures/tls/server-key.pem');
        final server = await SecureServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
          context,
        );
        final sockets = <SecureSocket>[];
        server.listen((socket) {
          sockets.add(socket);
          socket.transform(frameTransformer).listen((f) {
            if (f.type == 2) {
              socket.add(Frame(2, info: '{"code":0}').encode());
            }
          }, onError: (Object _) {});
        }, onError: (Object _) {});
        final events = <Map<String, dynamic>>[];
        final engine = ProxyEngine(onEvent: events.add);
        addTearDown(() async {
          await engine.disconnect();
          for (final s in sockets) {
            s.destroy();
          }
          await server.close();
        });
        await engine.connect(
          ClientConfig(
            server: hostname,
            port: server.port,
            certificatePath: 'test/fixtures/tls/server.pem',
          ),
          const Secrets(license: 'test-license'),
        );
        await until(
          () => events.any(
            (e) =>
                e['state'] == (hostname == 'localhost' ? 'connected' : 'error'),
          ),
        );
        if (hostname != 'localhost') {
          expect(events.any((e) => e['state'] == 'connected'), false);
          expect(events.last['detail'], contains('TLS'));
        }
      },
    );
  }
}
