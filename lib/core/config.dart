import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:yaml/yaml.dart';

String newId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class ClientConfig {
  ClientConfig({
    this.server = '',
    this.port = 9002,
    this.ssl = true,
    String? clientId,
    this.reconnectSeconds = 10,
    this.unlimited = false,
    this.udpPortRange = '10000-10500',
    this.readIdleSeconds = 120,
    this.heartbeatSeconds = 20,
    this.allIdleSeconds = 0,
    this.certificatePath = '',
  }) : clientId = clientId ?? newId();
  final String server, clientId, udpPortRange, certificatePath;
  final int port,
      reconnectSeconds,
      readIdleSeconds,
      heartbeatSeconds,
      allIdleSeconds;
  final bool ssl, unlimited;

  factory ClientConfig.fromJson(Map map) => ClientConfig(
    server: map['server'] as String? ?? '',
    port: map['port'] as int? ?? 9002,
    ssl: map['ssl'] as bool? ?? true,
    clientId: map['clientId'] as String?,
    reconnectSeconds: map['reconnectSeconds'] as int? ?? 10,
    unlimited: map['unlimited'] as bool? ?? false,
    udpPortRange: map['udpPortRange'] as String? ?? '10000-10500',
    readIdleSeconds: map['readIdleSeconds'] as int? ?? 120,
    heartbeatSeconds: map['heartbeatSeconds'] as int? ?? 20,
    allIdleSeconds: map['allIdleSeconds'] as int? ?? 0,
    certificatePath: map['certificatePath'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'server': server,
    'port': port,
    'ssl': ssl,
    'clientId': clientId,
    'reconnectSeconds': reconnectSeconds,
    'unlimited': unlimited,
    'udpPortRange': udpPortRange,
    'readIdleSeconds': readIdleSeconds,
    'heartbeatSeconds': heartbeatSeconds,
    'allIdleSeconds': allIdleSeconds,
    'certificatePath': certificatePath,
  };
  ClientConfig copyWith(Map<String, dynamic> updates) =>
      ClientConfig.fromJson({...toJson(), ...updates});
  (int, int)? get udpRange {
    final parts = udpPortRange.split('-');
    if (parts.length != 2) {
      return null;
    }
    final a = int.tryParse(parts[0]), b = int.tryParse(parts[1]);
    return a != null && b != null && a > 0 && b > a && b <= 65535
        ? (a, b)
        : null;
  }

  Map<String, String> validate({required bool hasLicense}) {
    final errors = <String, String>{};
    if (server.trim().isEmpty ||
        server.contains(RegExp(r'[\s/\\]')) ||
        server.contains('://')) {
      errors['server'] = '请填写域名或 IP，不包含协议和路径';
    }
    if (port < 1 || port > 65535) {
      errors['port'] = '端口应为 1–65535';
    }
    if (!hasLicense) {
      errors['license'] = '请填写 License';
    }
    if (clientId.isEmpty || clientId.contains(RegExp(r'[,\r\n]'))) {
      errors['clientId'] = '客户端标识不能为空或包含分隔符';
    }
    if (reconnectSeconds < 1 || reconnectSeconds > 86400) {
      errors['reconnectSeconds'] = '重连间隔应为 1–86400 秒';
    }
    if (udpRange == null) {
      errors['udpPortRange'] = 'UDP 范围应包含至少两个有效端口';
    }
    for (final entry in {
      'readIdleSeconds': readIdleSeconds,
      'heartbeatSeconds': heartbeatSeconds,
      'allIdleSeconds': allIdleSeconds,
    }.entries) {
      if (entry.value < 0 || entry.value > 86400) {
        errors[entry.key] = '空闲时间应为 0–86400 秒';
      }
    }
    return errors;
  }
}

class Secrets {
  const Secrets({this.license = '', this.storePassword = ''});
  final String license, storePassword;
  String get hint => license.isEmpty
      ? '尚未设置'
      : license.length <= 4
      ? '••••'
      : '•••• •••• ${license.substring(license.length - 4)}';
  Map<String, String> toJson() => {
    'license': license,
    'storePassword': storePassword,
  };
  factory Secrets.fromJson(Map map) => Secrets(
    license: map['license'] as String? ?? '',
    storePassword: map['storePassword'] as String? ?? '',
  );
}

class ImportPreview {
  ImportPreview(this.config, this.secrets, this.notes, this.blockers);
  final ClientConfig config;
  final Secrets secrets;
  final List<String> notes, blockers;
}

ImportPreview importConfig(
  String source, {
  required String baseDirectory,
  required Map<String, String> environment,
}) {
  if (utf8.encode(source).length > 1024 * 1024) {
    throw const FormatException('配置不能超过 1 MiB');
  }
  final root = loadYaml(source);
  if (root is! Map) {
    throw const FormatException('配置应为 JSON 或 YAML 对象');
  }
  if (root['config'] is Map) {
    final config = ClientConfig.fromJson(root['config'] as Map);
    return ImportPreview(config, const Secrets(), [
      '此配置不含凭证，请重新填写 License',
    ], []);
  }
  final proxy = root['neutrino']?['proxy'];
  if (proxy is! Map || proxy['tunnel'] is! Map) {
    throw const FormatException('没有找到 neutrino.proxy.tunnel 配置');
  }
  final tunnel = proxy['tunnel'] as Map;
  final protocol = proxy['protocol'] as Map? ?? {};
  final udp = proxy['client']?['udp'] as Map? ?? {};
  final retry = tunnel['reconnection'] as Map? ?? {};
  final blockers = <String>[];
  String text(dynamic raw, String fallback) {
    if (raw == null) {
      return fallback;
    }
    var value = raw.toString();
    value = value.replaceAllMapped(RegExp(r'\$\{([^}:]+)(?::([^}]*))?\}'), (m) {
      final resolved = environment[m[1]] ?? m[2];
      if (resolved == null) {
        blockers.add('缺少环境变量 ${m[1]}');
      }
      return resolved ?? '';
    });
    return value;
  }

  int number(dynamic raw, int fallback) {
    final result = int.tryParse(text(raw, '$fallback'));
    if (result == null) {
      throw const FormatException('配置中的数字格式无效');
    }
    return result;
  }

  bool flag(dynamic raw, bool fallback) {
    final value = text(raw, '$fallback');
    if (value != 'true' && value != 'false') {
      throw const FormatException('配置中的布尔值应为 true/false');
    }
    return value == 'true';
  }

  for (final e in {
    'max-frame-length': 2097152,
    'length-field-offset': 0,
    'length-field-length': 4,
    'initial-bytes-to-strip': 0,
    'length-adjustment': 0,
  }.entries) {
    if (number(protocol[e.key], e.value) != e.value) {
      blockers.add('暂不支持非默认 ${e.key}');
    }
  }
  if (text(protocol['water-mark'], '').isNotEmpty) {
    blockers.add('暂不支持自定义 water-mark');
  }
  var certificate = text(tunnel['jks-path'], 'classpath:/test.jks');
  if (certificate == 'classpath:/test.jks') {
    certificate = '';
  } else if (certificate.startsWith('classpath:')) {
    blockers.add('仅支持内置 classpath:/test.jks');
  } else if (certificate.isNotEmpty && !File(certificate).isAbsolute) {
    certificate = '$baseDirectory${Platform.pathSeparator}$certificate';
  }
  final id = text(tunnel['client-id'], '');
  final config = ClientConfig(
    server: text(tunnel['server-ip'], 'localhost'),
    port: number(tunnel['server-port'], 9002),
    ssl: flag(tunnel['ssl-enable'], true),
    clientId: id.isEmpty ? null : id,
    reconnectSeconds: number(retry['interval-seconds'], 10),
    unlimited: flag(retry['unlimited'], false),
    udpPortRange: text(udp['puppet-port-range'], '10000-10500'),
    readIdleSeconds: number(protocol['read-idle-time'], 120),
    heartbeatSeconds: number(protocol['write-idle-time'], 20),
    allIdleSeconds: number(protocol['all-idle-time-seconds'], 0),
    certificatePath: certificate,
  );
  final secrets = Secrets(
    license: text(tunnel['license-key'], ''),
    storePassword: text(tunnel['key-store-password'], '123456'),
  );
  blockers.addAll(
    config.validate(hasLicense: secrets.license.isNotEmpty).values,
  );
  return ImportPreview(config, secrets, [
    '原文件保持不变；凭证仅在确认保存后写入系统安全存储',
    'Netty 线程数与 Solon 日志参数不直接执行；Dart 使用异步调度与脱敏日志',
    'TLS 会检查证书链、有效期和服务器名称；旧 Java 客户端未显式开启名称检查',
  ], blockers);
}
