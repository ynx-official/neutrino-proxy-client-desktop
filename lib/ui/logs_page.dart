import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../application/controller.dart';
import 'theme.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.model});
  final AppState model;
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String filter = 'all', query = '';
  bool paused = false;
  List<Map<String, dynamic>> frozen = [];
  Future<void> export(List<Map<String, dynamic>> logs) async {
    try {
      final location = await getSaveLocation(
        suggestedName: 'neutrino-logs.txt',
        acceptedTypeGroups: [
          const XTypeGroup(label: '日志', extensions: ['txt']),
        ],
      );
      if (location == null) {
        return;
      }
      final text = logs
          .map(
            (log) =>
                '${DateTime.fromMillisecondsSinceEpoch(log['time'] as int).toIso8601String()} [${log['level']}] ${log['message']}',
          )
          .join('\n');
      await XFile.fromData(
        utf8.encode(text),
        mimeType: 'text/plain',
      ).saveTo(location.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('日志导出失败，请检查文件权限')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = paused ? frozen : widget.model.logs;
    final logs = all
        .where(
          (e) =>
              (filter == 'all' || e['level'] == filter) &&
              (e['message'] as String).toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList()
        .reversed
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '运行日志',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
              TextButton.icon(
                onPressed: () => export(logs.reversed.toList()),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('导出日志'),
              ),
            ],
          ),
        ),
        Row(
          children: [
            SizedBox(
              width: 112,
              child: DropdownButtonFormField<String>(
                initialValue: filter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('全部级别')),
                  DropdownMenuItem(value: 'info', child: Text('信息')),
                  DropdownMenuItem(value: 'warn', child: Text('警告')),
                  DropdownMenuItem(value: 'error', child: Text('错误')),
                ],
                onChanged: (v) => setState(() => filter = v ?? 'all'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: '搜索日志',
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => setState(() {
                paused = !paused;
                if (paused) {
                  frozen = widget.model.logs;
                }
              }),
              icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
              label: Text(paused ? '继续' : '暂停'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        Expanded(
          child: logs.isEmpty
              ? const Center(
                  child: Text('暂无日志', style: TextStyle(color: muted)),
                )
              : ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clockText(log['time'] as int),
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'Consolas',
                              color: muted,
                            ),
                          ),
                          const SizedBox(width: 18),
                          SizedBox(
                            width: 40,
                            child: Text(
                              {
                                    'info': '信息',
                                    'warn': '警告',
                                    'error': '错误',
                                  }[log['level']] ??
                                  '信息',
                              style: TextStyle(
                                fontSize: 12,
                                color: log['level'] == 'error' ? danger : muted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              log['message'] as String,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${logs.length} 条日志 · 仅保留本次运行最近 500 条',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
