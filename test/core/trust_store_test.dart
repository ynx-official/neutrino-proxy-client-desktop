import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/core/trust_store.dart';

void main() {
  test(
    'official Java JKS extracts trusted certificates without Java',
    () async {
      final jks = await File('assets/test.jks').readAsBytes();
      final certs = readTrustCertificates(jks, '123456');
      expect(certs, isNotEmpty);
      expect(certs.first.first, 0x30);
      expect(
        () => readTrustCertificates(jks, 'incorrect'),
        throwsFormatException,
      );
      final damaged = [...jks]..[20] ^= 1;
      expect(
        () => readTrustCertificates(damaged, '123456'),
        throwsFormatException,
      );
    },
  );
  test('truncated JKS cannot overrun its input', () async {
    final jks = await File('assets/test.jks').readAsBytes();
    for (final end in [0, 3, 12, 100, jks.length - 1]) {
      expect(
        () => readTrustCertificates(jks.sublist(0, end), '123456'),
        throwsFormatException,
      );
    }
  });
}
