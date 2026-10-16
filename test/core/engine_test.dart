import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/core/config.dart';
import 'package:neutrino_proxy_client_desktop/core/engine.dart';
import 'package:neutrino_proxy_client_desktop/core/protocol.dart';

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late ServerSocket server;
  late ProxyEngine engine;
  late List<Map<String, dynamic>> events;
  late List<Socket> peers;
  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    events = [];
    peers = [];
    engine = ProxyEngine(onEvent: events.add);
  });
  tearDown(() async {
    await engine.disconnect();
    for (final peer in peers) {
      peer.destroy();
    }
    await server.close();
  });
  ClientConfig config({bool unlimited = false}) => ClientConfig(
    server: '127.0.0.1',
    port: server.port,
    ssl: false,
    clientId: 'java-compatible',
    reconnectSeconds: 1,
    unlimited: unlimited,
    heartbeatSeconds: 1,
  );
  const secrets = Secrets(license: 'fictional-license');
  bool state(String value) => events.any((e) => e['state'] == value);

  test('auth uses license,clientId; heartbeat and explicit cancellation release socket', () async {
    final received = <Frame>[];
    server.listen((socket) {
      peers.add(socket);
      socket.transform(frameTransformer).listen((frame) {
        received.add(frame);
        if (frame.type == 2) {
          socket.add(Frame(2, info: '{"code":0}').encode());
        }
      }, onError: (_) {});
    });
    await engine.connect(config(), secrets);
    await until(() => state('connected'));
    expect(received.first.info, 'fictional-license,java-compatible');
    expect(received.first.serial, 0);
    await until(() => received.any((f) => f.type == 1));
    await engine.disconnect();
    expect(events.last['state'], 'idle');
    final count = peers.length;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(peers.length, count);
    expect(events.toString(), isNot(contains('fictional-license')));
  });
  test('AUTH_FAILED stops retry without exiting app', () async {
    server.listen((socket) {
      peers.add(socket);
      socket.listen((_) {
        socket.add(
          Frame(
            2,
            info: '{"code":1,"licenseKey":"fictional-license"}',
          ).encode(),
        );
      }, onError: (_) {});
    });
    await engine.connect(config(), secrets);
    await until(() => state('error'));
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(peers, hasLength(1));
    expect(events.toString(), isNot(contains('fictional-license')));
  });
  test('CONNECT_FAILED retries even when unlimited is false', () async {
    server.listen((socket) {
      peers.add(socket);
      socket.listen((_) {
        socket.add(Frame(2, info: '{"code":2}').encode());
      }, onError: (_) {});
    });
    await engine.connect(config(), secrets);
    await until(() => peers.length >= 2);
    expect(state('reconnecting'), true);
  });
  test(
    'TCP binds visitor@license and transfers binary bytes both ways',
    () async {
      final target = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final targets = <Socket>[];
      target.listen((s) {
        targets.add(s);
        s.listen((data) => s.add(data), onError: (_) {});
      });
      addTearDown(() async {
        for (final s in targets) {
          s.destroy();
        }
        await target.close();
      });
      final done = Completer<void>();
      server.listen((socket) {
        peers.add(socket);
        socket.transform(frameTransformer).listen((f) {
          if (f.type == 2) {
            socket.add(Frame(2, info: '{"code":0}').encode());
            socket.add(
              Frame(
                3,
                info: 'visitor',
                data: utf8.encode('127.0.0.1:${target.port}'),
              ).encode(),
            );
          } else if (f.type == 3) {
            expect(f.info, 'visitor@fictional-license');
            socket.add(
              Frame(5, info: 'visitor', data: [0, 255, 1, 2, 3]).encode(),
            );
          } else if (f.type == 5) {
            expect(f.info, 'visitor');
            expect(f.data, [0, 255, 1, 2, 3]);
            if (!done.isCompleted) {
              done.complete();
            }
          }
        }, onError: (_) {});
      });
      await engine.connect(config(), secrets);
      await done.future.timeout(const Duration(seconds: 5));
      await engine.disconnect();
      expect(events.last['state'], 'idle');
    },
  );
  test(
    'target failure is reported without dropping healthy control session',
    () async {
      final unavailable = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = unavailable.port;
      await unavailable.close();
      final done = Completer<void>();
      server.listen((socket) {
        peers.add(socket);
        socket.transform(frameTransformer).listen((f) {
          if (f.type == 2) {
            socket.add(Frame(2, info: '{"code":0}').encode());
            socket.add(
              Frame(
                3,
                info: 'missing',
                data: utf8.encode('127.0.0.1:$port'),
              ).encode(),
            );
          }
          if (f.type == 4 && !done.isCompleted) {
            expect(f.info, 'missing');
            done.complete();
          }
        }, onError: (_) {});
      });
      await engine.connect(config(), secrets);
      await done.future.timeout(const Duration(seconds: 5));
      expect(events.last['state'], 'connected');
    },
  );
  test(
    'UDP tunnel puts license in data and preserves return metadata',
    () async {
      final target = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      target.listen((event) {
        if (event == RawSocketEvent.read) {
          final d = target.receive();
          if (d != null) {
            target.send(d.data, d.address, d.port);
          }
        }
      });
      addTearDown(target.close);
      final done = Completer<void>();
      final meta = {
        'visitorId': 'udp-visitor',
        'visitorIp': '127.0.0.1',
        'visitorPort': 12345,
        'serverPort': 7001,
        'targetIp': '127.0.0.1',
        'targetPort': target.port,
        'proxyResponses': 1,
        'proxyTimeoutMs': 1000,
      };
      server.listen((socket) {
        peers.add(socket);
        socket.transform(frameTransformer).listen((f) {
          if (f.type == 2) {
            socket.add(Frame(2, info: '{"code":0}').encode());
            socket.add(Frame(8, info: jsonEncode(meta)).encode());
          }
          if (f.type == 8) {
            expect(utf8.decode(f.data), 'fictional-license');
            socket.add(
              Frame(16, info: jsonEncode(meta), data: [3, 0, 255]).encode(),
            );
          }
          if (f.type == 16) {
            expect(f.data, [3, 0, 255]);
            final reply = jsonDecode(f.info) as Map;
            expect(reply['visitorId'], 'udp-visitor');
            expect(reply['visitorPort'], 12345);
            if (!done.isCompleted) {
              done.complete();
            }
          }
        }, onError: (_) {});
      });
      await engine.connect(config(), secrets);
      await done.future.timeout(const Duration(seconds: 5));
    },
  );
  test(
    'immediate disconnect prevents late authentication or reconnect',
    () async {
      server.listen((s) {
        peers.add(s);
        s.listen((_) {}, onError: (_) {});
      });
      await engine.connect(config(), secrets);
      await engine.disconnect();
      final count = events.length;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(events.last['state'], 'idle');
      expect(events.length, count);
    },
  );
}
