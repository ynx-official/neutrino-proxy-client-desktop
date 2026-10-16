import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import 'engine_bridge.dart';
import 'storage.dart';

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
  AppController({required this.store, required this.engine});
  final ConfigStore store;
  final EnginePort engine;
  Secrets _secrets = const Secrets();
  bool _credentialsPending = false;
  @override
  AppState build() {
    final subscription = engine.events.listen((event) {
      if ((event['revision'] as int? ?? 0) <
          (state.engine['revision'] as int? ?? 0)) {
        return;
      }
      final phase = event['state'];
      if (phase == 'idle') {
        _credentialsPending = false;
      }
      final active = event['activeConfig'];
      final pending =
          phase != 'idle' &&
          (_credentialsPending ||
              active != null &&
                  jsonEncode(active) != jsonEncode(state.config.toJson()));
      state = state.copy(engine: event, pending: pending);
    });
    ref.onDispose(subscription.cancel);
    return AppState(config: ClientConfig());
  }

  Future<void> initialize() async {
    try {
      final saved = await store.load();
      _secrets = saved.secrets;
      state = state.copy(
        config: saved.config,
        hasLicense: _secrets.license.isNotEmpty,
        hint: _secrets.hint,
        ready: true,
        error: '',
      );
    } catch (_) {
      state = state.copy(error: '无法读取配置或系统凭证。请检查文件权限与安全存储后重试。');
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

  Future<bool> connect() => _run(() async {
    _credentialsPending = false;
    await engine.connect(state.config, _secrets);
  });
  Future<bool> disconnect() => _run(engine.disconnect);
  Future<bool> save(
    ClientConfig config, {
    String? license,
    String? password,
    bool reconnect = false,
  }) => _run(() async {
    final next = Secrets(
      license: license ?? _secrets.license,
      storePassword: password ?? _secrets.storePassword,
    );
    final errors = config.validate(hasLicense: next.license.isNotEmpty);
    if (errors.isNotEmpty) {
      throw FormatException(errors.values.join('；'));
    }
    final saved = await store.save(config, next);
    _credentialsPending =
        state.active &&
        (_credentialsPending ||
            next.license != _secrets.license ||
            next.storePassword != _secrets.storePassword);
    _secrets = next;
    state = state.copy(
      config: saved,
      hasLicense: next.license.isNotEmpty,
      hint: next.hint,
      pending:
          state.active &&
          (_credentialsPending ||
              jsonEncode(saved.toJson()) !=
                  jsonEncode(state.displayedConfig.toJson())),
    );
    if (reconnect) {
      _credentialsPending = false;
      await engine.connect(saved, next);
    }
  });
}
