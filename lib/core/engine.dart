import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'protocol.dart';
import 'transport.dart';
import 'trust_store.dart';
import 'udp.dart';

class _SessionFailure implements Exception {
  const _SessionFailure(this.message, {this.retry = true});
  final String message;
  final bool retry;
}

class ProxyEngine {
  ProxyEngine({required this.onEvent, this.builtinTrust = const []});
  final void Function(Map<String, dynamic>) onEvent;
  final List<int> builtinTrust;
  ConnectionScope? _scope;
  Timer? _retry;
  int _generation = 0, _revision = 0;
  String _state = 'idle', _detail = '填写连接信息，开始第一次连接';
  int? _connectedAt, _retryAt;
  ClientConfig? _active;
  final List<Map<String, dynamic>> _logs = [];

  void _emit() {
    onEvent({
      'state': _state,
      'detail': _detail,
      'revision': ++_revision,
      'connectedAt': _connectedAt,
      'retryAt': _retryAt,
      'activeConfig': _active?.toJson(),
      'logs': _logs.map((e) => Map<String, dynamic>.from(e)).toList(),
    });
  }

  void _status(String state, String detail) {
    _state = state;
    _detail = detail;
    _retryAt = null;
    if (state != 'connected') {
      _connectedAt = null;
    }
    _emit();
  }

  void _log(String level, String message) {
    _logs.add({
      'id': _revision + 1,
      'time': DateTime.now().millisecondsSinceEpoch,
      'level': level,
      'message': message.length > 512 ? message.substring(0, 512) : message,
    });
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    _emit();
  }

  Future<void> connect(ClientConfig config, Secrets secrets) async {
    final errors = config.validate(hasLicense: secrets.license.isNotEmpty);
    if (errors.isNotEmpty) {
      throw FormatException(errors.values.join('；'));
    }
    if (secrets.license.contains(RegExp(r'[,\r\n]'))) {
      throw const FormatException('License 包含不支持的分隔符');
    }
    await disconnect(notify: false);
    final generation = _generation;
    _active = config;
    _status('connecting', '正在连接服务器');
    unawaited(_attempt(config, secrets, generation));
  }

  Future<void> disconnect({bool notify = true}) async {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _scope?.close();
    _scope = null;
    _active = null;
    _connectedAt = null;
    _retryAt = null;
    if (notify) {
      _status('idle', '连接已断开，可随时重新连接');
      _log('info', '连接已断开');
    }
  }

  Future<SecurityContext?> _security(
    ClientConfig config,
    Secrets secrets,
  ) async {
    if (!config.ssl) {
      return null;
    }
    final builtin = config.certificatePath.isEmpty;
    List<int> bytes;
    if (builtin) {
      bytes = builtinTrust;
    } else {
      final file = File(config.certificatePath);
      if (await file.length() > 4 * 1024 * 1024) {
        throw const FormatException('证书文件超过 4 MiB');
      }
      bytes = await file.readAsBytes();
    }
    final certs = readTrustCertificates(
      bytes,
      builtin ? '123456' : secrets.storePassword,
    );
    final context = SecurityContext(withTrustedRoots: false);
    for (final cert in certs) {
      context.setTrustedCertificatesBytes(certificatePem(cert));
    }
    return context;
  }

  Future<void> _attempt(
    ClientConfig config,
    Secrets secrets,
    int generation,
  ) async {
    if (generation != _generation) {
      return;
    }
    final scope = ConnectionScope();
    _scope = scope;
    var message = '连接已中断';
    var retry = true;
    try {
      SecurityContext? security;
      try {
        security = await _security(config, secrets);
      } catch (_) {
        throw const _SessionFailure('无法读取信任证书，请检查证书文件和密码', retry: false);
      }
      if (generation != _generation) {
        return;
      }
      _status('connecting', '正在连接服务器');
      final socket = await scope.dial(
        config.server,
        config.port,
        security: security,
      );
      final wire = Wire(socket, config);
      scope.cleanups.add(wire.close);
      final udp = UdpPool(config, scope, _log);
      _status('authenticating', '正在验证 License');
      final authDeadline = Timer(const Duration(seconds: 15), wire.close);
      scope.cleanups.add(authDeadline.cancel);
      await wire.send(Frame(2, info: '${secrets.license},${config.clientId}'));
      var authenticated = false;
      final jobs = <Future<void>>{};
      void forward(Future<void> job) {
        jobs.add(job);
        unawaited(job.whenComplete(() => jobs.remove(job)));
      }

      await for (final frame in wire.frames) {
        if (scope.closed) {
          break;
        }
        wire.received();
        if (frame.type == 2) {
          final result = jsonDecode(frame.info) as Map;
          final code = result['code'];
          if (code == 1) {
            throw _SessionFailure(
              'License 验证失败，请检查凭证',
              retry: config.unlimited,
            );
          }
          if (code == 2 || code == 3) {
            throw const _SessionFailure('服务器暂时拒绝连接，将按配置重试');
          }
          if (code != 0) {
            throw const _SessionFailure('服务器返回未知认证结果', retry: false);
          }
          authenticated = true;
          authDeadline.cancel();
          _connectedAt = DateTime.now().millisecondsSinceEpoch;
          _status('connected', '连接已建立');
          _log('info', 'License 验证通过，连接已建立');
        } else if (frame.type == 6) {
          final error = jsonDecode(frame.info) as Map;
          if (error['code'] == 1) {
            throw const _SessionFailure('服务器已撤销认证，请检查 License', retry: false);
          }
          _log('warn', '服务器报告隧道错误');
        } else if (frame.type == 4) {
          break;
        } else if (authenticated && (frame.type == 3 || frame.type == 8)) {
          if (jobs.length >= 256) {
            _log('warn', '并发连接达到本地资源上限');
            await wire.send(Frame(4, info: frame.info));
            continue;
          }
          forward(_forward(frame, config, secrets, scope, security, wire, udp));
        }
        // Heartbeats and structurally valid unhandled types are ignored as in
        // the Java dispatcher; they must not disconnect a healthy session.
      }
    } on Cancelled {
      return;
    } on _SessionFailure catch (e) {
      message = e.message;
      retry = e.retry;
    } on HandshakeException {
      message = 'TLS 验证失败，请检查证书信任、有效期和服务器名称';
      retry = false;
    } on FormatException {
      message = '隧道消息格式无效';
    } on TimeoutException {
      message = '连接服务器超时';
    } catch (_) {
      message = '无法连接服务器或连接已中断，请检查网络与端口';
    } finally {
      scope.close();
    }
    if (generation != _generation) {
      return;
    }
    _log('error', message);
    if (!retry) {
      _status('error', message);
      return;
    }
    _state = 'reconnecting';
    _detail = message;
    _connectedAt = null;
    _retryAt =
        DateTime.now().millisecondsSinceEpoch + config.reconnectSeconds * 1000;
    _emit();
    _retry = Timer(Duration(seconds: config.reconnectSeconds), () {
      if (generation == _generation) {
        unawaited(_attempt(config, secrets, generation));
      }
    });
  }

  Future<void> _forward(
    Frame request,
    ClientConfig config,
    Secrets secrets,
    ConnectionScope scope,
    SecurityContext? security,
    Wire control,
    UdpPool udp,
  ) async {
    Socket? target, tunnel;
    Wire? wire;
    try {
      if (request.type == 3) {
        final endpoint = utf8.decode(request.data);
        final colon = endpoint.lastIndexOf(':');
        if (colon < 1) {
          throw const FormatException('目标地址无效');
        }
        var host = endpoint.substring(0, colon);
        if (host.startsWith('[') && host.endsWith(']')) {
          host = host.substring(1, host.length - 1);
        }
        target = await scope.dial(
          host,
          int.parse(endpoint.substring(colon + 1)),
        );
      }
      tunnel = await scope.dial(config.server, config.port, security: security);
      wire = Wire(tunnel, config);
      if (request.type == 8) {
        final meta = jsonDecode(request.info) as Map;
        final binding = {
          for (final key in [
            'visitorId',
            'serverPort',
            'targetIp',
            'targetPort',
          ])
            key: meta[key],
        };
        await wire.send(
          Frame(
            8,
            info: jsonEncode(binding),
            data: utf8.encode(secrets.license),
          ),
        );
        await udp.forward(wire);
      } else {
        await wire.send(Frame(3, info: '${request.info}@${secrets.license}'));
        final outbound = wire;
        final local = target!;
        Future<void> upstream() async {
          await for (final bytes in local) {
            // Awaiting the drain pauses the source stream and bounds buffering.
            await outbound.send(Frame(5, info: request.info, data: bytes));
          }
        }

        Future<void> downstream() async {
          await for (final frame in outbound.frames) {
            outbound.received();
            if (frame.type == 4) {
              break;
            }
            if (frame.type == 5) {
              local.add(frame.data);
              await local.flush();
            }
          }
        }

        await Future.any([upstream(), downstream()]);
      }
    } on Cancelled {
      /* The entire generation is being torn down. */
    } catch (_) {
      if (!scope.closed) {
        _log('warn', request.type == 3 ? 'TCP 目标或数据隧道连接失败' : 'UDP 数据隧道失败');
        try {
          await control.send(Frame(4, info: request.info));
        } catch (_) {}
      }
    } finally {
      wire?.close();
      scope.release(target);
      scope.release(tunnel);
    }
  }
}
