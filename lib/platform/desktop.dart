import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../application/controller.dart';
import '../background/client.dart';
import '../ui/app.dart';

/// A window may detach; only the native host may stop the application.
class DesktopLifecycle with WindowListener {
  DesktopLifecycle(this.container, this.backend, this.shellKey);
  final ProviderContainer container;
  final ProcessClientBackend backend;
  final GlobalKey<AppShellState> shellKey;
  bool _closing = false;
  bool _trayReady = true;
  bool _hostAlive = true;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Future<void> start() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    if (Platform.isMacOS) {
      const MethodChannel('cn.neutrino.lifecycle')
          .setMethodCallHandler((call) async {
            if (call.method == 'requestQuit') {
              await _event({'kind': 'prepareQuit'});
            }
          });
    }
    _subscription = backend.hostEvents.stream.listen(
      (m) => unawaited(_event(m)),
    );
    await backend.notifyHost('uiReady');
    if (backend.activation.isNotEmpty) await _event(backend.activation);
  }

  Future<void> _event(Map<String, dynamic> m) async {
    if (m['kind'] == 'activate') {
      _trayReady = m['trayReady'] != false;
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
      if (m['route'] == 'logs') await shellKey.currentState?.navigate(1);
      if (m['route'] == 'settings') await shellKey.currentState?.navigate(2);
    } else if (m['kind'] == 'prepareQuit') {
      // Unsaved-edit confirmation must remain reachable if the UI is minimized.
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
      await _close(quitApplication: true);
    } else if (m['kind'] == 'hostLost') {
      _hostAlive = false;
      container.read(appProvider.notifier).reportError('后台进程已退出，请重新打开应用。');
    }
  }

  @override
  void onWindowClose() => unawaited(_close(quitApplication: !_trayReady));
  Future<void> _close({required bool quitApplication}) async {
    if (_closing) return;
    if (container.read(appProvider).busy) {
      container.read(appProvider.notifier).reportError('正在处理操作，请完成后再关闭窗口。');
      return;
    }
    _closing = true;
    try {
      if (!await (shellKey.currentState?.confirmLeave() ??
          Future.value(true))) {
        return;
      }
      if (quitApplication && _hostAlive) {
        await backend.notifyHost('quitApproved');
      }
      await _subscription?.cancel();
      await backend.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      await windowManager.destroy();
      exit(0);
    } finally {
      _closing = false;
    }
  }
}
