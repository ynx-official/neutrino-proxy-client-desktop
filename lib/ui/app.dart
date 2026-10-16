import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/controller.dart';
import '../core/config.dart';
import 'connection_page.dart';
import 'logs_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class NeutrinoApp extends StatelessWidget {
  const NeutrinoApp({super.key, this.shellKey});
  final GlobalKey<AppShellState>? shellKey;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Neutrino',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: AppShell(key: shellKey),
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => AppShellState();
}

class AppShellState extends ConsumerState<AppShell> {
  int page = 0, editGeneration = 0;
  bool dirty = false;
  Future<bool> confirmLeave() async {
    if (!dirty) {
      return true;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('当前连接设置尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      setState(() {
        dirty = false;
        editGeneration++;
      });
    }
    return result ?? false;
  }

  Future<void> navigate(int value) async {
    if (value == page) {
      return;
    }
    if (await confirmLeave() && mounted) {
      setState(() => page = value);
    }
  }

  Future<void> importFile() async {
    if (!await confirmLeave()) {
      return;
    }
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: '客户端配置', extensions: ['yml', 'yaml', 'json']),
        ],
      );
      if (file == null) {
        return;
      }
      if (await file.length() > 1024 * 1024) {
        throw const FormatException('配置过大');
      }
      final preview = importConfig(
        await file.readAsString(),
        baseDirectory: File(file.path).parent.path,
        environment: Platform.environment,
      );
      if (!mounted) {
        return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入连接配置'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${preview.config.server}:${preview.config.port}'),
                  const SizedBox(height: 12),
                  Text(
                    'SSL：${preview.config.ssl ? '开启' : '关闭'} · License：${preview.secrets.license.isEmpty ? '未提供' : '已读取'}',
                  ),
                  for (final note in preview.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        note,
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ),
                  for (final blocker in preview.blockers)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        blocker,
                        style: const TextStyle(color: danger),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: preview.blockers.isEmpty
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('应用配置'),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) {
        final saved = await ref
            .read(appProvider.notifier)
            .save(
              preview.config,
              license: preview.secrets.license.isEmpty
                  ? null
                  : preview.secrets.license,
              password: preview.secrets.storePassword.isEmpty
                  ? null
                  : preview.secrets.storePassword,
            );
        if (saved && mounted) {
          setState(() {
            page = 2;
            editGeneration++;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法导入配置，请检查文件格式、大小及内容')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appProvider),
        controller = ref.read(appProvider.notifier);
    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: hairline)),
            ),
            child: Row(
              children: [
                Image.asset('assets/logo.png', width: 30, height: 30),
                const SizedBox(width: 12),
                const Text(
                  'Neutrino',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                for (final entry in [
                  (0, '连接', 'connection'),
                  (1, '日志', 'logs'),
                  (2, '设置', 'settings'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 22),
                    child: InkWell(
                      key: Key('nav-${entry.$3}'),
                      onTap: () => navigate(entry.$1),
                      child: Container(
                        height: 72,
                        width: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: page == entry.$1
                                  ? ink
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          entry.$2,
                          style: TextStyle(
                            color: page == entry.$1 ? ink : muted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (model.error.isNotEmpty)
            Container(
              color: const Color(0xfffff7f3),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: danger, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      model.error,
                      style: const TextStyle(color: danger),
                    ),
                  ),
                  if (!model.ready)
                    TextButton(
                      onPressed: controller.initialize,
                      child: const Text('重试'),
                    )
                  else
                    IconButton(
                      onPressed: controller.dismissError,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                  child: !model.ready
                      ? const Center(
                          child: Text(
                            '正在读取本机配置…',
                            style: TextStyle(color: muted),
                          ),
                        )
                      : switch (page) {
                          1 => LogsPage(model: model),
                          2 => SettingsPage(
                            key: ValueKey(editGeneration),
                            model: model,
                            onDirty: (value) => dirty = value,
                            onImport: importFile,
                            onSave: (config, license, password, reconnect) =>
                                controller.save(
                                  config,
                                  license: license,
                                  password: password,
                                  reconnect: reconnect,
                                ),
                          ),
                          _ => ConnectionPage(
                            model: model,
                            onSettings: () => navigate(2),
                            onLogs: () => navigate(1),
                            onImport: importFile,
                            onConnect: () => controller.connect(),
                            onDisconnect: () => controller.disconnect(),
                          ),
                        },
                ),
              ),
            ),
          ),
          const SizedBox(
            height: 30,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 24),
                child: Text(
                  'v0.1.0',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
