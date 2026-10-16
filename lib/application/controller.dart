import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import 'engine_bridge.dart';
import 'storage.dart';
import '../background/backend.dart';
import '../background/service.dart';

const stateLabels = {
  'idle': '尚未连接',
  'connecting': '正在连接',
  'authenticating': '正在验证',
  'connected': '已连接',
  'reconnecting': '等待重连',
  'stopping': '正在断开',
  'error': '连接失败',
};

class AppState {
  AppState({
    required this.config,
    this.hasLicense = false,
    this.hint = '尚未设置',
    this.engine = const {},
    this.ready = false,
    this.busy = false,
    this.error = '',
    this.pending = false,
  });
  final ClientConfig config;
  final bool hasLicense, ready, busy, pending;
  final String hint, error;
  final Map<String, dynamic> engine;
  String get phase => engine['state'] as String? ?? 'idle';
  String get label => stateLabels[phase] ?? '尚未连接';
  bool get active => [
    'connecting',
    'authenticating',
    'connected',
    'reconnecting',
    'stopping',
  ].contains(phase);
  ClientConfig get displayedConfig => engine['activeConfig'] is Map && active
      ? ClientConfig.fromJson(engine['activeConfig'] as Map)
      : config;
  List<Map<String, dynamic>> get logs => (engine['logs'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  AppState copy({
    ClientConfig? config,
    bool? hasLicense,
    String? hint,
    Map<String, dynamic>? engine,
    bool? ready,
    bool? busy,
    String? error,
    bool? pending,
  }) => AppState(
    config: config ?? this.config,
    hasLicense: hasLicense ?? this.hasLicense,
    hint: hint ?? this.hint,
    engine: engine ?? this.engine,
    ready: ready ?? this.ready,
    busy: busy ?? this.busy,
    error: error ?? this.error,
    pending: pending ?? this.pending,
  );
}

final appProvider = NotifierProvider<AppController, AppState>(
  () => throw StateError('Application dependencies have not been initialized'),
);

class AppController extends Notifier<AppState> {
  AppController({
    ConfigStore? store,
    EnginePort? engine,
    ClientBackend? backend,
  }) : backend = backend ?? ClientService(store: store!, engine: engine);
  final ClientBackend backend;
  @override
  AppState build() {
    final subscription = backend.events.listen(_apply);
    ref.onDispose(subscription.cancel);
    return AppState(config: ClientConfig());
  }

  void _apply(Map<String, dynamic> value) {
    state = state.copy(
      config: value['config'] is Map
          ? ClientConfig.fromJson(value['config'] as Map)
          : null,
      hasLicense: value['hasLicense'] as bool? ?? false,
      hint: value['hint'] as String? ?? '尚未设置',
      engine: Map<String, dynamic>.from(value['engine'] as Map? ?? {}),
      ready: value['ready'] == true,
      pending: value['pending'] == true,
      error: value['error'] as String? ?? '',
    );
  }

  Future<void> initialize() async {
    try {
      await backend.initialize();
      _apply(backend.snapshot);
    } catch (_) {
      state = state.copy(error: '无法连接后台内核，请检查安装包或重新打开应用。');
    }
  }

  void dismissError() {
    state = state.copy(error: '');
  }

  void reportError(String message) {
    state = state.copy(error: message);
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (state.busy || !state.ready) {
      return false;
    }
    state = state.copy(busy: true, error: '');
    try {
      await action();
      return true;
    } catch (_) {
      state = state.copy(error: '操作未完成，请检查连接参数、文件权限或系统安全存储。');
      return false;
    } finally {
      state = state.copy(busy: false);
    }
  }

  Future<bool> connect() => _run(backend.connect);
  Future<bool> disconnect() => _run(backend.disconnect);
  Future<bool> save(
    ClientConfig config, {
    String? license,
    String? password,
    bool reconnect = false,
  }) => _run(
    () => backend.save(
      config,
      license: license,
      password: password,
      reconnect: reconnect,
    ),
  );
}
