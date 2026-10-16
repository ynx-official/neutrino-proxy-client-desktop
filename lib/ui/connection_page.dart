import 'dart:async';

import 'package:flutter/material.dart';

import '../application/controller.dart';
import 'theme.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.model,
    required this.onSettings,
    required this.onLogs,
    required this.onConnect,
    required this.onDisconnect,
    required this.onImport,
  });
  final AppState model;
  final VoidCallback onSettings, onLogs, onConnect, onDisconnect, onImport;
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late final Timer timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model, c = m.displayedConfig;
    final start = m.engine['connectedAt'] as int?;
    final seconds = start == null
        ? 0
        : ((DateTime.now().millisecondsSinceEpoch - start) ~/ 1000).clamp(
            0,
            99999999,
          );
    final duration = start == null
        ? '—'
        : '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final retry = m.engine['retryAt'] as int?;
    final remaining = retry == null
        ? 0
        : ((retry - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(
            0,
            86400,
          );
    final recent = m.logs.reversed.take(3).toList().reversed.toList();
    final enabled = m.ready && !m.busy;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: m.phase == 'connected'
                                ? const Color(0xff43bd89)
                                : m.phase == 'error'
                                ? danger
                                : muted,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Flexible(
                          child: Text(
                            m.label,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (c.server.isNotEmpty)
                            Tooltip(
                              message: '${c.server}:${c.port}',
                              child: Text(
                                '${c.server}:${c.port}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 13,
                                  color: muted,
                                ),
                              ),
                            )
                          else
                            const Text(
                              '配置你的服务器，建立安全连接',
                              style: TextStyle(color: muted),
                            ),
                          if (['error', 'reconnecting'].contains(m.phase))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                m.engine['detail'] as String? ?? '',
                                style: const TextStyle(color: danger),
                              ),
                            ),
                          if (retry != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '$remaining 秒后重试',
                                style: const TextStyle(color: muted),
                              ),
                            ),
                          if (c.server.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextButton.icon(
                                onPressed: widget.onSettings,
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  size: 16,
                                ),
                                label: const Text('编辑连接'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (m.phase == 'reconnecting')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilledButton(
                        onPressed: enabled ? widget.onConnect : null,
                        child: const Text('立即重试'),
                      ),
                    ),
                  if (m.active)
                    OutlinedButton.icon(
                      onPressed: enabled ? widget.onDisconnect : null,
                      icon: const Icon(Icons.power_settings_new, size: 17),
                      label: Text(
                        m.phase == 'connected'
                            ? '断开连接'
                            : m.phase == 'reconnecting'
                            ? '停止重连'
                            : '取消连接',
                      ),
                    )
                  else if (m.hasLicense && c.server.isNotEmpty)
                    FilledButton.icon(
                      onPressed: enabled ? widget.onConnect : null,
                      icon: const Icon(Icons.power_settings_new, size: 17),
                      label: Text(m.phase == 'error' ? '重新连接' : '连接'),
                    )
                  else ...[
                    FilledButton(
                      onPressed: enabled ? widget.onSettings : null,
                      child: const Text('填写连接信息'),
                    ),
                    TextButton(
                      onPressed: enabled ? widget.onImport : null,
                      child: const Text('导入配置'),
                    ),
                  ],
                  if (c.server.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const Text(
                      '本次连接',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      duration,
                      style: const TextStyle(
                        fontSize: 20,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(),
          if (c.server.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                children: [
                  Expanded(child: _meta('SSL', c.ssl ? '已启用' : '未启用')),
                  Expanded(child: _meta('License', m.hint)),
                ],
              ),
            ),
            const Divider(),
          ],
          if (m.pending)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('新配置将在下次连接时生效', style: TextStyle(color: muted)),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('最近事件', style: TextStyle(fontSize: 16)),
              TextButton.icon(
                onPressed: widget.onLogs,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right, size: 16),
                label: const Text('全部日志'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('暂无事件', style: TextStyle(color: muted)),
            ),
          for (final log in recent) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Icon(
                    log['level'] == 'info' ? Icons.check : Icons.error_outline,
                    size: 16,
                    color: log['level'] == 'info' ? success : danger,
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: Text(log['message'] as String)),
                  const SizedBox(width: 16),
                  Text(
                    clockText(log['time'] as int),
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _meta(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 8),
      Text(value),
    ],
  );
}
