import 'dart:async';
import 'dart:isolate';

import '../core/config.dart';
import '../core/engine.dart';

abstract interface class EnginePort {
  Stream<Map<String, dynamic>> get events;
  Future<void> connect(ClientConfig config, Secrets secrets);
  Future<void> disconnect();
  Future<void> dispose();
}

class EngineBridge implements EnginePort {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _pending = <int, Completer<void>>{};
  final _receive = ReceivePort();
  final _ready = Completer<SendPort>();
  Isolate? _isolate;
  int _next = 0;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  Future<void> start(List<int> builtinTrust) async {
    _receive.listen((dynamic message) {
      if (message is SendPort) {
        _ready.complete(message);
        return;
      }
      if (message is List) {
        for (final pending in _pending.values) {
          pending.completeError(StateError('网络内核异常退出'));
        }
        _pending.clear();
        _events.add({
          'state': 'error',
          'detail': '网络内核异常退出，请重新启动应用',
          'revision': 0x7fffffff,
          'logs': <Map<String, dynamic>>[],
        });
        return;
      }
      final data = Map<String, dynamic>.from(message as Map);
      if (data['event'] != null) {
        _events.add(Map<String, dynamic>.from(data['event'] as Map));
      } else {
        final completer = _pending.remove(data['id']);
        if (data['error'] != null) {
          completer?.completeError(StateError(data['error'] as String));
        } else {
          completer?.complete();
        }
      }
    });
    _isolate = await Isolate.spawn(
      _engineMain,
      [_receive.sendPort, builtinTrust],
      onError: _receive.sendPort,
      errorsAreFatal: true,
    );
    await _ready.future;
  }

  Future<void> _command(
    String op, [
    ClientConfig? config,
    Secrets? secrets,
  ]) async {
    final port = await _ready.future;
    final id = ++_next;
    final completer = Completer<void>();
    _pending[id] = completer;
    port.send({
      'id': id,
      'op': op,
      'config': config?.toJson(),
      'secrets': secrets?.toJson(),
    });
    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('网络内核未响应');
      },
    );
  }

  @override
  Future<void> connect(ClientConfig config, Secrets secrets) =>
      _command('connect', config, secrets);
  @override
  Future<void> disconnect() => _command('disconnect');
  @override
  Future<void> dispose() async {
    try {
      await disconnect();
    } finally {
      _isolate?.kill(priority: Isolate.immediate);
      _receive.close();
      await _events.close();
    }
  }
}

Future<void> _engineMain(List<dynamic> args) async {
  final output = args[0] as SendPort;
  final inbox = ReceivePort();
  final engine = ProxyEngine(
    builtinTrust: List<int>.from(args[1] as List),
    onEvent: (event) => output.send({'event': event}),
  );
  output.send(inbox.sendPort);
  // Serialized commands prevent save/connect/disconnect races. Network work
  // itself remains asynchronous and does not block the Flutter UI isolate.
  await for (final raw in inbox) {
    final message = raw as Map;
    try {
      if (message['op'] == 'connect') {
        await engine.connect(
          ClientConfig.fromJson(message['config'] as Map),
          Secrets.fromJson(message['secrets'] as Map),
        );
      } else {
        await engine.disconnect();
      }
      output.send({'id': message['id']});
    } catch (_) {
      output.send({'id': message['id'], 'error': '网络操作失败，请检查配置后重试'});
    }
  }
}
