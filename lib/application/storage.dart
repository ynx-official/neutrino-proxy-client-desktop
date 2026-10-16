import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../core/config.dart';

abstract interface class CredentialVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SavedConfig {
  const SavedConfig(this.config, this.secrets);
  final ClientConfig config;
  final Secrets secrets;
}

class ConfigStore {
  ConfigStore(this.directory, this.vault);
  final Directory directory;
  final CredentialVault vault;
  String _credentialId = '';
  File get file => File('${directory.path}/config.json');
  Future<SavedConfig> load() async {
    if (!await file.exists()) {
      final config = ClientConfig();
      await save(config, const Secrets());
      return SavedConfig(config, const Secrets());
    }
    if (await file.length() > 1024 * 1024) {
      throw const FormatException('保存的配置文件过大');
    }
    final data = jsonDecode(await file.readAsString()) as Map;
    if (data['schemaVersion'] != 1) {
      throw const FormatException('配置版本暂不支持');
    }
    final config = ClientConfig.fromJson(data['config'] as Map);
    _credentialId = data['credentialId'] as String? ?? '';
    if (_credentialId.isEmpty) {
      return SavedConfig(config, const Secrets());
    }
    final stored = await vault.read(_credentialId);
    if (stored == null) {
      throw const FormatException('系统凭证不可用，请恢复安全存储后重试');
    }
    return SavedConfig(config, Secrets.fromJson(jsonDecode(stored) as Map));
  }

  Future<ClientConfig> save(ClientConfig config, Secrets secrets) async {
    await directory.create(recursive: true);
    if (config.certificatePath.isNotEmpty) {
      final source = File(config.certificatePath);
      if (await source.length() > 4 * 1024 * 1024) {
        throw const FormatException('证书文件不能超过 4 MiB');
      }
      final bytes = await source.readAsBytes();
      final certificates = Directory('${directory.path}/certificates');
      await certificates.create(recursive: true);
      // Import while the picker grants access, so a sandboxed macOS restart
      // does not depend on a temporary grant for the original external file.
      final local = File('${certificates.path}/${sha256.convert(bytes)}.cert');
      if (!await local.exists()) {
        await local.writeAsBytes(bytes, flush: true);
      }
      config = config.copyWith({'certificatePath': local.path});
    }
    final id = secrets.license.isEmpty && secrets.storePassword.isEmpty
        ? ''
        : newId();
    if (id.isNotEmpty) {
      await vault.write(id, jsonEncode(secrets.toJson()));
    }
    try {
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'config': config.toJson(),
          'credentialId': id,
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (_) {
      if (id.isNotEmpty) {
        try {
          await vault.delete(id);
        } catch (_) {}
      }
      rethrow;
    }
    final previous = _credentialId;
    _credentialId = id;
    // Delete the former secret only after its replacement is durably referenced.
    if (previous.isNotEmpty) {
      try {
        await vault.delete(previous);
      } catch (_) {}
    }
    return config;
  }
}
