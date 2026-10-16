import 'dart:async';
import 'dart:convert';

import '../application/engine_bridge.dart';
import '../application/storage.dart';
import '../core/config.dart';
import '../core/engine.dart';
import 'backend.dart';

class DirectEngine implements EnginePort {
  DirectEngine(List<int> trust) {
    engine = ProxyEngine(builtinTrust: trust, onEvent: _events.add);
  }
  late final ProxyEngine engine;
  final _events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  Future<void> connect(ClientConfig config, Secrets secrets) =>
      engine.connect(config, secrets);
  @override
  Future<void> disconnect() => engine.disconnect();
  @override
  Future<void> dispose() async {
    await engine.disconnect();
    await _events.close();
  }
}

/// The service, never a window, owns saved credentials and active connection state.
class ClientService implements ClientBackend {
  ClientService({
    required this.store,
    EnginePort? engine,
    List<int> trust = const [],
  }) : engine = engine ?? DirectEngine(trust) {
    _subscription = this.engine.events.listen((event) {
      _engine = event;
      if (event['state'] == 'idle') _credentialsPending = false;
      _publish();
    });
  }
  final ConfigStore store;
  final EnginePort engine;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final _events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  ClientConfig _config = ClientConfig();
  Secrets _secrets = const Secrets();
  Map<String, dynamic> _engine = {'state': 'idle', 'logs': <dynamic>[]};
  bool _ready = false, _credentialsPending = false;
  String _error = '';
  int _revision = 0, _configRevision = 0;
  bool get _active => [
    'connecting',
    'authenticating',
    'connected',
    'reconnecting',
    'stopping',
  ].contains(_engine['state']);
  @override
  Map<String, dynamic> get snapshot => {
    'revision': _revision,
    'configRevision': _configRevision,
    'config': _config.toJson(),
    'hasLicense': _secrets.license.isNotEmpty,
    'hint': _secrets.hint,
    'ready': _ready,
    'error': _error,
    'pending':
        _active &&
        (_credentialsPending ||
            _engine['activeConfig'] != null &&
                jsonEncode(_engine['activeConfig']) !=
                    jsonEncode(_config.toJson())),
    'engine': _engine,
  };
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  void _publish() {
    _revision++;
    _events.add(snapshot);
  }

  @override
  Future<void> initialize() async {
    try {
      final saved = await store.load();
      _config = saved.config;
      _secrets = saved.secrets;
      _ready = true;
      _error = '';
    } catch (_) {
      _error = '无法读取配置或系统凭证。请检查文件权限与安全存储后重试。';
    }
    _publish();
  }

  @override
  Future<void> connect() async {
    if (!_ready) throw StateError('Configuration unavailable');
    _credentialsPending = false;
    await engine.connect(_config, _secrets);
  }

  @override
  Future<void> disconnect() => engine.disconnect();
  @override
  Future<void> save(
    ClientConfig config, {
    String? license,
    String? password,
    bool reconnect = false,
  }) async {
    if (!_ready) throw StateError('Configuration unavailable');
    final next = Secrets(
      license: license ?? _secrets.license,
      storePassword: password ?? _secrets.storePassword,
    );
    final errors = config.validate(hasLicense: next.license.isNotEmpty);
    if (errors.isNotEmpty) throw FormatException(errors.values.join('；'));
    final saved = await store.save(config, next);
    _credentialsPending =
        _active &&
        (_credentialsPending ||
            next.license != _secrets.license ||
            next.storePassword != _secrets.storePassword);
    _config = saved;
    _configRevision++;
    _secrets = next;
    _publish();
    if (reconnect) await connect();
  }

  @override
  Future<void> close() async {
    await engine.dispose();
    await _subscription.cancel();
    await _events.close();
  }
}
