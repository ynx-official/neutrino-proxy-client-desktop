import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/core/config.dart';

void main() {
  test('official defaults and actionable validation', () {
    final config = ClientConfig();
    expect(config.port, 9002);
    expect(config.ssl, true);
    expect(config.reconnectSeconds, 10);
    expect(config.readIdleSeconds, 120);
    expect(config.heartbeatSeconds, 20);
    expect(
      config.validate(hasLicense: false).keys,
      containsAll(['server', 'license']),
    );
    expect(
      ClientConfig(
        server: 'https://bad/path',
        port: 0,
        udpPortRange: '99-98',
      ).validate(hasLicense: true).keys,
      containsAll(['server', 'port', 'udpPortRange']),
    );
  });
  test(
    'YAML import resolves environment and reports unsupported protocol options',
    () {
      final preview = importConfig(
        '''
neutrino:
  proxy:
    tunnel:
      server-ip: \${SERVER_IP:localhost}
      license-key: \${LICENSE_KEY:}
      client-id: fixed-client
      reconnection:
        unlimited: true
    protocol:
      length-field-offset: 1
''',
        baseDirectory: '.',
        environment: {'SERVER_IP': '127.0.0.1', 'LICENSE_KEY': 'test-secret'},
      );
      expect(preview.config.server, '127.0.0.1');
      expect(preview.config.clientId, 'fixed-client');
      expect(preview.secrets.license, 'test-secret');
      expect(preview.blockers.join(), contains('length-field-offset'));
      expect(preview.notes.join(), isNot(contains('test-secret')));
    },
  );
  test('non-default idle times import and secret-free serialized config', () {
    final preview = importConfig(
      '''
neutrino:
  proxy:
    tunnel:
      server-ip: localhost
      license-key: fictional-key
    protocol:
      read-idle-time: 0
      write-idle-time: 2
      all-idle-time-seconds: 9
''',
      baseDirectory: '.',
      environment: {},
    );
    expect(preview.config.readIdleSeconds, 0);
    expect(preview.config.allIdleSeconds, 9);
    expect(
      preview.config.toJson().toString(),
      isNot(contains('fictional-key')),
    );
    expect(preview.blockers, isEmpty);
  });
  test('short credentials never appear in masked hints', () {
    expect(Secrets(license: 'abc').hint, '••••');
    expect(Secrets(license: '12345678').hint, endsWith('5678'));
  });
}
