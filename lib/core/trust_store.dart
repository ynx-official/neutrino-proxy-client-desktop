import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Reads certificates only. JKS integrity follows OpenJDK JavaKeyStore;
/// encrypted private keys are skipped and never decrypted or used.
List<Uint8List> readTrustCertificates(List<int> input, String password) {
  if (input.isEmpty || input.length > 4 * 1024 * 1024) {
    throw const FormatException('证书文件为空或超过 4 MiB');
  }
  final bytes = Uint8List.fromList(input);
  if (bytes.length >= 4 &&
      ByteData.sublistView(bytes).getUint32(0) == 0xfeedfeed) {
    if (bytes.length < 32) {
      throw const FormatException('JKS 文件被截断');
    }
    final body = bytes.sublist(0, bytes.length - 20);
    final passwordBytes = <int>[];
    for (final c in password.codeUnits) {
      passwordBytes.addAll([c >> 8, c & 255]);
    }
    final expected = sha1.convert([
      ...passwordBytes,
      ...utf8.encode('Mighty Aphrodite'),
      ...body,
    ]).bytes;
    var difference = 0;
    for (var i = 0; i < 20; i++) {
      difference |= expected[i] ^ bytes[body.length + i];
    }
    if (difference != 0) {
      throw const FormatException('JKS 密码错误或文件已损坏');
    }
    final reader = _Reader(body)..take(4);
    final version = reader.integer();
    if (version != 1 && version != 2) {
      throw const FormatException('不支持的 JKS 版本');
    }
    final count = reader.integer();
    if (count > 10000) {
      throw const FormatException('JKS 条目过多');
    }
    final certs = <Uint8List>[];
    void certificate() {
      if (version == 2) {
        reader.text();
      }
      final der = reader.take(reader.integer());
      if (der.isEmpty || der.first != 0x30) {
        throw const FormatException('证书格式无效');
      }
      certs.add(der);
    }

    for (var i = 0; i < count; i++) {
      final tag = reader.integer();
      reader.text();
      reader.take(8);
      if (tag == 1) {
        reader.take(reader.integer());
        final chain = reader.integer();
        if (chain > 10000) {
          throw const FormatException('JKS 证书链过长');
        }
        for (var j = 0; j < chain; j++) {
          certificate();
        }
      } else if (tag == 2) {
        certificate();
      } else {
        throw const FormatException('JKS 条目类型无效');
      }
    }
    if (reader.offset != body.length || certs.isEmpty) {
      throw const FormatException('JKS 没有有效信任证书或含异常数据');
    }
    return certs;
  }
  if (bytes.first == 0x30) {
    return [bytes];
  }
  final pem = utf8.decode(bytes);
  final matches = RegExp(
    r'-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----',
  ).allMatches(pem);
  final result = matches
      .map((m) => base64.decode(m[1]!.replaceAll(RegExp(r'\s'), '')))
      .toList();
  if (result.isEmpty) {
    throw const FormatException('请选择 JKS、PEM 或 DER 信任证书');
  }
  return result;
}

List<int> certificatePem(List<int> der) => utf8.encode(
  '-----BEGIN CERTIFICATE-----\n${base64.encode(der)}\n-----END CERTIFICATE-----\n',
);

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  Uint8List take(int count) {
    if (count < 0 || count > bytes.length - offset) {
      throw const FormatException('JKS 文件被截断');
    }
    final value = Uint8List.sublistView(bytes, offset, offset + count);
    offset += count;
    return value;
  }

  int integer() => ByteData.sublistView(take(4)).getUint32(0);
  void text() {
    final size = ByteData.sublistView(take(2)).getUint16(0);
    take(size);
  }
}
