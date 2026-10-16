import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../application/controller.dart';
import '../application/engine_bridge.dart';
import '../application/storage.dart';
import '../ui/app.dart';

class SystemVault implements CredentialVault {
  const SystemVault();
  // Use the standard macOS login Keychain without a provisioning profile or
  // cross-application Keychain Sharing entitlement.
  static const storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  String _key(String key) => 'neutrino.flutter.$key';
  @override
  Future<String?> read(String key) => storage.read(key: _key(key));
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: _key(key), value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: _key(key));
}

class DesktopLifecycle with WindowListener, TrayListener {
  DesktopLifecycle(this.container, this.engine, this.shellKey);
  final ProviderContainer container;
  final EnginePort engine;
  final GlobalKey<AppShellState> shellKey;
  bool _quitting = false, _trayReady = false, _closing = false;
  ProviderSubscription<AppState>? _subscription;
  Future<void> _menuTail = Future.value();
  String _menuSignature = '';

  Future<void> start() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
      );
      _trayReady = true;
      _subscription = container.listen(appProvider, (_, next) {
        _updateMenu(next);
      }, fireImmediately: true);
    } catch (_) {
      container.read(appProvider.notifier).reportError('系统托盘初始化失败，关闭窗口将退出应用。');
    }
  }

  void _updateMenu(AppState state) {
    final signature =
        '${state.phase}|${state.busy}|${state.ready}|${state.displayedConfig.server}:${state.displayedConfig.port}';
    if (signature == _menuSignature) {
      return;
    }
    _menuSignature = signature;
    _menuTail = _menuTail
        .then((_) async {
          if (_quitting) {
            return;
          }
          final current = container.read(appProvider),
              config = current.displayedConfig;
          await trayManager.setToolTip('Neutrino · ${current.label}');
          await trayManager.setContextMenu(
            Menu(
              items: [
                MenuItem(label: 'Neutrino · ${current.label}', disabled: true),
                MenuItem(
                  label: config.server.isEmpty
                      ? '尚未配置服务器'
                      : '${config.server}:${config.port}',
                  disabled: true,
                ),
                MenuItem.separator(),
                MenuItem(key: 'open', label: '打开主窗口'),
                MenuItem(key: 'logs', label: '查看日志'),
                MenuItem(
                  key: current.active ? 'disconnect' : 'connect',
                  label: current.phase == 'connected'
                      ? '断开连接'
                      : current.active
                      ? '停止连接'
                      : '连接',
                  disabled: current.busy || !current.ready,
                ),
                MenuItem.separator(),
                MenuItem(key: 'quit', label: '退出'),
              ],
            ),
          );
        })
        .catchError((Object _) {
          _menuSignature = '';
        });
  }

  Future<void> show([int? page]) async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
    if (page != null) {
      await shellKey.currentState?.navigate(page);
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(show());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    unawaited(_trayAction(menuItem.key));
  }

  Future<void> _trayAction(String? key) async {
    final current = container.read(appProvider),
        controller = container.read(appProvider.notifier);
    switch (key) {
      case 'open':
        await show();
      case 'logs':
        await show(1);
      case 'connect':
        if (current.active || current.busy) {
          return;
        }
        if (!current.hasLicense || current.config.server.isEmpty) {
          await show(2);
        } else {
          await controller.connect();
        }
      case 'disconnect':
        if (current.active && !current.busy) {
          await controller.disconnect();
        }
      case 'quit':
        await quit();
    }
  }

  @override
  void onWindowClose() {
    unawaited(_close());
  }

  Future<void> _close() async {
    if (_closing || _quitting) {
      return;
    }
    _closing = true;
    try {
      if (await shellKey.currentState?.confirmLeave() ?? true) {
        if (_trayReady) {
          await windowManager.hide();
        } else {
          await quit();
        }
      }
    } finally {
      _closing = false;
    }
  }

  Future<void> quit() async {
    if (_quitting) {
      return;
    }
    if (!await (shellKey.currentState?.confirmLeave() ?? Future.value(true))) {
      return;
    }
    _quitting = true;
    _subscription?.close();
    try {
      await engine.dispose();
    } finally {
      if (_trayReady) {
        await trayManager.destroy();
      }
      await windowManager.destroy();
      exit(0);
    }
  }
}
