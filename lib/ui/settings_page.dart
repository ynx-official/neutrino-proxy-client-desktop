import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../application/controller.dart';
import '../core/config.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.model,
    required this.onDirty,
    required this.onImport,
    required this.onSave,
  });
  final AppState model;
  final ValueChanged<bool> onDirty;
  final VoidCallback onImport;
  final Future<bool> Function(ClientConfig, String?, String?, bool) onSave;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final fields = <String, TextEditingController>{};
  bool ssl = true, unlimited = false, advanced = false, visible = false;
  String certificate = '', saved = '';
  Map<String, String> errors = {};
  @override
  void initState() {
    super.initState();
    final c = widget.model.config;
    for (final e in {...c.toJson(), 'license': '', 'password': ''}.entries) {
      fields[e.key] = TextEditingController(text: e.value.toString());
    }
    ssl = c.ssl;
    unlimited = c.unlimited;
    certificate = c.certificatePath;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void changed() {
    widget.onDirty(true);
    setState(() {
      saved = '';
    });
  }

  Future<void> save(bool reconnect) async {
    final values = widget.model.config.toJson();
    for (final key in ['server', 'clientId', 'udpPortRange']) {
      values[key] = fields[key]!.text.trim();
    }
    for (final key in [
      'port',
      'reconnectSeconds',
      'readIdleSeconds',
      'heartbeatSeconds',
      'allIdleSeconds',
    ]) {
      values[key] = int.tryParse(fields[key]!.text) ?? -1;
    }
    values['ssl'] = ssl;
    values['unlimited'] = unlimited;
    values['certificatePath'] = certificate;
    final config = ClientConfig.fromJson(values);
    final license = fields['license']!.text.trim(),
        password = fields['password']!.text;
    setState(
      () => errors = config.validate(
        hasLicense: license.isNotEmpty || widget.model.hasLicense,
      ),
    );
    if (errors.isNotEmpty) {
      setState(
        () => advanced = errors.keys.any(
          (k) => !['server', 'port', 'license'].contains(k),
        ),
      );
      return;
    }
    final result = await widget.onSave(
      config,
      license.isEmpty ? null : license,
      password.isEmpty ? null : password,
      reconnect,
    );
    if (result && mounted) {
      fields['license']!.clear();
      fields['password']!.clear();
      widget.onDirty(false);
      setState(() => saved = reconnect ? '配置已保存，正在连接' : '配置已保存');
    }
  }

  Future<void> selectCertificate() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '信任证书',
          extensions: ['jks', 'pem', 'crt', 'cer', 'der'],
        ),
      ],
    );
    if (file != null && mounted) {
      setState(() => certificate = file.path);
      changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.model.ready && !widget.model.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '连接设置',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
              TextButton.icon(
                onPressed: enabled ? widget.onImport : null,
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: const Text('导入配置'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: field('服务器地址', 'server', hint: 'edge.example.com'),
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: field('端口', 'port')),
                  ],
                ),
                const SizedBox(height: 16),
                field(
                  'License',
                  'license',
                  hint: widget.model.hasLicense ? '已保存 · 留空不修改' : '输入 License',
                  secret: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 20),
                    const SizedBox(width: 10),
                    const Text('SSL 加密'),
                    const Spacer(),
                    Switch(
                      value: ssl,
                      onChanged: enabled
                          ? (v) {
                              setState(() => ssl = v);
                              changed();
                            }
                          : null,
                    ),
                  ],
                ),
                if (ssl) ...[
                  const Text('信任证书', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: hairline),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message: certificate.isEmpty
                                ? '官方客户端内置信任证书'
                                : certificate,
                            child: Text(
                              certificate.isEmpty
                                  ? '内置证书'
                                  : certificate.split(RegExp(r'[/\\]')).last,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: enabled ? selectCertificate : null,
                        child: const Text('选择文件'),
                      ),
                    ],
                  ),
                  if (certificate.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setState(() => certificate = '');
                          changed();
                        },
                        child: const Text('使用内置证书'),
                      ),
                    ),
                  if (certificate.toLowerCase().endsWith('.jks'))
                    field('证书库密码', 'password', hint: '已保存时留空不修改', secret: true),
                ],
                const SizedBox(height: 12),
                const Divider(),
                TextButton.icon(
                  onPressed: () {
                    setState(() => advanced = !advanced);
                  },
                  icon: const Icon(Icons.tune, size: 18),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('高级设置'),
                      const SizedBox(width: 8),
                      Icon(
                        advanced ? Icons.expand_less : Icons.chevron_right,
                        size: 17,
                      ),
                    ],
                  ),
                ),
                if (advanced) ...[
                  field('客户端 ID', 'clientId'),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: field('重连间隔（秒）', 'reconnectSeconds')),
                      const SizedBox(width: 20),
                      Expanded(child: field('心跳写空闲（秒）', 'heartbeatSeconds')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: field('读取空闲超时（秒）', 'readIdleSeconds')),
                      const SizedBox(width: 20),
                      Expanded(child: field('全空闲超时（秒）', 'allIdleSeconds')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  field('UDP 端口范围', 'udpPortRange'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'License 验证失败后仍持续重试',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: unlimited,
                    onChanged: enabled
                        ? (v) {
                            setState(() => unlimited = v ?? false);
                            changed();
                          }
                        : null,
                  ),
                  if (ssl)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'TLS 会验证证书链、有效期和服务器名称。名称不匹配时请使用与证书一致的服务器地址。',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  saved.isNotEmpty
                      ? saved
                      : widget.model.active
                      ? '保存后下次连接生效'
                      : '凭证安全保存在本机',
                  style: TextStyle(
                    fontSize: 12,
                    color: saved.isNotEmpty ? success : muted,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: enabled ? () => save(false) : null,
                child: const Text('保存配置'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: enabled ? () => save(true) : null,
                child: Text(widget.model.active ? '保存并重连' : '保存并连接'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget field(String label, String key, {String? hint, bool secret = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            key: Key(key),
            controller: fields[key],
            enabled: widget.model.ready && !widget.model.busy,
            obscureText: secret && !visible,
            autocorrect: false,
            enableSuggestions: !secret,
            onChanged: (_) => changed(),
            decoration: InputDecoration(
              hintText: hint,
              errorText: errors[key],
              suffixIcon: secret
                  ? IconButton(
                      tooltip: visible ? '隐藏内容' : '显示内容',
                      onPressed: () => setState(() => visible = !visible),
                      icon: Icon(
                        visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 19,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      );
}
