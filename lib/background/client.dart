import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/config.dart';
import 'backend.dart';
import 'ipc.dart';

class ProcessClientBackend implements ClientBackend {
  ProcessClientBackend(Stream<List<int>> input, StreamSink<List<int>> output)
    : _writer = MessageWriter(output) {
    _subscription = input
        .transform(messageDecoder)
        .listen(_receive, onDone: _lost, onError: (Object _) => _lost());
  }
  final MessageWriter _writer;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final _events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final hostEvents = StreamController<Map<String, dynamic>>.broadcast();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Map<String, dynamic> _snapshot = {}, activation = {};
  int _next = 0;
  bool _closed = false;
  @override
  Map<String, dynamic> get snapshot => _snapshot;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  void _accept(Map<String, dynamic> value) {
    if (value['epoch'] == _snapshot['epoch'] &&
        (value['revision'] as int? ?? 0) <
            (_snapshot['revision'] as int? ?? 0)) {
      return;
    }
    _snapshot = value;
    _events.add(value);
  }

  void _receive(Map<String, dynamic> m) {
    switch (m['kind']) {
      case 'state':
        _accept(Map<String, dynamic>.from(m['data'] as Map));
      case 'response':
        final pending = _pending.remove(m['id']);
        if (m['error'] != null) {
          pending?.completeError(StateError(m['error'] as String));
        } else {
          final result = Map<String, dynamic>.from(m['result'] as Map);
          _accept(result);
          pending?.complete(result);
        }
      case 'activate':
        activation = m;
        hostEvents.add(m);
      case 'prepareQuit':
        hostEvents.add(m);
    }
  }

  void _lost() {
    if (_closed) return;
    for (final pending in _pending.values) {
      pending.completeError(StateError('后台连接已关闭'));
    }
    _pending.clear();
    _accept({
      ..._snapshot,
      'epoch': 'lost',
      'ready': false,
      'error': '后台进程已退出，请重新打开应用。',
    });
    hostEvents.add({'kind': 'hostLost'});
  }

  Future<Map<String, dynamic>> _call(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_closed) throw StateError('Client detached');
    final id = 'ui-${++_next}';
    final pending = Completer<Map<String, dynamic>>();
    _pending[id] = pending;
    try {
      // Observe the reply immediately: parent EOF can fail it while the output
      // pipe is still blocked. Waiting for the write first loses that failure.
      final results = await Future.wait<dynamic>([
        _writer.send({
          'kind': 'request',
          'version': ipcVersion,
          'id': id,
          'op': op,
          'params': params,
        }),
        pending.future,
      ], eagerError: true).timeout(const Duration(seconds: 20));
      return results[1] as Map<String, dynamic>;
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> notifyHost(String kind) => _writer.send({'kind': kind});
  @override
  Future<void> initialize() async {
    await _call('attach');
  }

  @override
  Future<void> connect() async {
    await _call('connect');
  }

  @override
  Future<void> disconnect() async {
    await _call('disconnect');
  }

  @override
  Future<void> save(
    ClientConfig config, {
    String? license,
    String? password,
    bool reconnect = false,
  }) async {
    final params = <String, dynamic>{
      'config': config.toJson(),
      'license': license,
      'password': password,
      'reconnect': reconnect,
      'revision': _snapshot['configRevision'],
    };
    final existing = _snapshot['config'] as Map?;
    if (config.certificatePath.isNotEmpty &&
        config.certificatePath != existing?['certificatePath']) {
      final file = File(config.certificatePath);
      if (await file.length() > 4 * 1024 * 1024) {
        throw const FormatException('证书文件不能超过 4 MiB');
      }
      params['certificate'] = base64Encode(await file.readAsBytes());
    }
    await _call('save', params);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    try {
      await _call('detach').timeout(const Duration(seconds: 2));
    } catch (_) {}
    _closed = true;
    await _subscription.cancel();
    for (final pending in _pending.values) {
      pending.completeError(StateError('Client detached'));
    }
    _pending.clear();
    await _events.close();
    await hostEvents.close();
    await _writer.close();
  }
}
