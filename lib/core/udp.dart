import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'protocol.dart';
import 'transport.dart';

class UdpPool {
  UdpPool(this.config, this.scope, this.log);
  final ClientConfig config;
  final ConnectionScope scope;
  final void Function(String, String) log;
  final _used = <int>{};
  Future<RawDatagramSocket>? _default;

  Future<RawDatagramSocket> _bind(int port) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: false,
    );
    if (scope.closed) {
      socket.close();
      throw const Cancelled();
    }
    return socket;
  }

  Future<RawDatagramSocket> _defaultSocket() => _default ??= (() async {
    final socket = await _bind(config.udpRange!.$1);
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        while (socket.receive() != null) {}
      }
    }, onError: (Object _) {});
    scope.cleanups.add(socket.close);
    return socket;
  })();

  Future<RawDatagramSocket?> _lease() async {
    final (first, last) = config.udpRange!;
    for (var port = first + 1; port <= last; port++) {
      if (!_used.add(port)) {
        continue;
      }
      try {
        return await _bind(port);
      } on SocketException {
        _used.remove(port);
      }
    }
    return null;
  }

  Future<void> forward(Wire wire) async {
    RawDatagramSocket? lease;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? expiry;
    Map<String, dynamic>? bound;
    var responses = 0;
    var finished = false;
    void end() {
      if (finished) {
        return;
      }
      finished = true;
      wire.close();
      expiry?.cancel();
      lease?.close();
    }

    void renew() {
      expiry?.cancel();
      if (bound != null) {
        expiry = Timer(
          Duration(milliseconds: bound['proxyTimeoutMs'] as int),
          end,
        );
      }
    }

    scope.cleanups.add(end);
    try {
      await for (final frame in wire.frames) {
        wire.received();
        if (frame.type == 4 || frame.type == 9) {
          break;
        }
        if (frame.type != 16) {
          continue;
        }
        if (frame.data.length > 65507) {
          throw const FormatException('UDP 数据报超过限制');
        }
        final meta = Map<String, dynamic>.from(jsonDecode(frame.info) as Map);
        final ip = meta['targetIp'] as String;
        final port = meta['targetPort'] as int;
        final expected = meta['proxyResponses'] as int? ?? 0;
        final timeout = meta['proxyTimeoutMs'] as int? ?? 0;
        if (port < 1 || port > 65535) {
          throw const FormatException('UDP 目标端口无效');
        }
        if (lease == null && expected != 0 && timeout > 0) {
          lease = await _lease();
          if (lease == null) {
            log('warn', 'UDP 回包端口不足，本次仅发送数据');
          } else {
            bound = meta;
            subscription = lease.listen(
              (event) async {
                if (event != RawSocketEvent.read || finished) {
                  return;
                }
                final packet = lease!.receive();
                if (packet == null) {
                  return;
                }
                // Pause the UDP source while the tunnel drains; queued datagrams
                // remain bounded by the OS receive buffer instead of a Dart list.
                lease.readEventsEnabled = false;
                try {
                  final reply = {
                    for (final key in [
                      'visitorId',
                      'visitorIp',
                      'visitorPort',
                      'serverPort',
                      'targetIp',
                      'targetPort',
                    ])
                      key: bound![key],
                    'proxyResponses': 0,
                    'proxyTimeoutMs': 0,
                  };
                  await wire.send(
                    Frame(16, info: jsonEncode(reply), data: packet.data),
                  );
                  responses++;
                  renew();
                  final limit = bound!['proxyResponses'] as int;
                  if (limit > 0 && responses >= limit) {
                    end();
                  }
                } catch (_) {
                  end();
                } finally {
                  if (!finished) {
                    lease!.readEventsEnabled = true;
                  }
                }
              },
              onError: (Object _) {
                end();
              },
            );
          }
        }
        final socket = lease ?? await _defaultSocket();
        final addresses = await scope.wait(
          InternetAddress.lookup(ip, type: InternetAddressType.IPv4),
        );
        if (scope.closed || finished) {
          break;
        }
        final sent = socket.send(frame.data, addresses.first, port);
        if (sent != frame.data.length) {
          throw const SocketException('UDP 数据发送失败');
        }
        if (lease != null) {
          responses = 0;
          renew();
        }
      }
    } finally {
      end();
      await subscription?.cancel();
      if (lease != null) {
        _used.remove(lease.port);
      }
      scope.cleanups.remove(end);
    }
  }
}
