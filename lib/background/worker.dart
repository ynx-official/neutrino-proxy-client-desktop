import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../application/storage.dart';
import '../core/config.dart';
import 'ipc.dart';
import 'service.dart';

class HostVault implements CredentialVault {
  HostVault(this.writer);
  final MessageWriter writer;
  final _pending = <String, Completer<dynamic>>{};
  int _id = 0;
  void receive(Map<String, dynamic> message) {
    final pending = _pending.remove(message['id']);
    if (message['error'] != null) {
      pending?.completeError(StateError('System vault unavailable'));
    } else {
      pending?.complete(message['result']);
    }
  }

  Future<dynamic> _call(String op, String key, [String? value]) async {
    final id = 'vault-${++_id}';
    final result = Completer<dynamic>();
    _pending[id] = result;
    try {
      await writer.send({
        'kind': 'vault',
        'id': id,
        'op': op,
        'key': 'neutrino.flutter.$key',
        'value': value,
      });
      return await result.future.timeout(const Duration(seconds: 15));
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Future<String?> read(String key) async => await _call('read', key) as String?;
  @override
  Future<void> write(String key, String value) async {
    await _call('write', key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _call('delete', key);
  }
}

Future<void> runWorker(List<String> args) async {
  if (args.length != 2) {
    exitCode = 64;
    return;
  }
  final directory = Directory('${args[0]}/neutrino-flutter');
  await directory.create(recursive: true);
  final lock = await File('${directory.path}/worker.lock')
      .open(mode: FileMode.append);
  await lock.lock(FileLock.exclusive);
  final writer = MessageWriter(stdout);
  final vault = HostVault(writer);
  final service = ClientService(
    store: ConfigStore(directory, vault),
    trust: await File(args[1]).readAsBytes(),
  );
  final epoch = newId();
  var attached = false, initialized = false, stopping = false;
  var session = '';
  Future<void> tail = Future.value();
  var queuedRequests = 0, queuedBytes = 0;
  Timer? emitTimer;
  final replies = <String, Map<String, dynamic>>{};
  Map<String, dynamic> snapshot({bool? includeLogs}) {
    final data = service.snapshot;
    return {
      ...data,
      'epoch': epoch,
      'engine': {
        ...data['engine'] as Map,
        if (!(includeLogs ?? attached)) 'logs': <dynamic>[],
      },
    };
  }

  Future<void> emit() => writer.send({'kind': 'state', 'data': snapshot()});
  final changes = service.events.listen((_) {
    emitTimer ??= Timer(const Duration(milliseconds: 50), () {
      emitTimer = null;
      if (!stopping) unawaited(emit().catchError((Object _) {}));
    });
  });
  Future<void> request(Map<String, dynamic> m) async {
    final key = '${m['session']}:${m['id']}';
    if (replies.containsKey(key)) {
      await writer.send(replies[key]!);
      return;
    }
    final response = <String, dynamic>{
      'kind': 'response',
      'id': m['id'],
      'session': m['session'],
      'source': m['source'],
    };
    try {
      if (m['version'] != ipcVersion) {
        throw const FormatException('IPC version mismatch');
      }
      final op = m['op'];
      final params = Map<String, dynamic>.from(m['params'] as Map? ?? {});
      if (!initialized) {
        await service.initialize();
        initialized = true;
      }
      switch (op) {
        case 'attach':
          attached = true;
          session = m['session'] as String? ?? '';
        case 'detach':
          if (m['session'] == session) {
            attached = false;
            replies.clear();
          }
        case 'snapshot':
          break;
        case 'connect':
          await service.connect();
        case 'disconnect':
          await service.disconnect();
        case 'save':
          if (params['revision'] != service.snapshot['configRevision']) {
            throw StateError('State changed; reload before saving');
          }
          var config = ClientConfig.fromJson(params['config'] as Map);
          if (params['certificate'] is String) {
            final bytes = base64Decode(params['certificate'] as String);
            if (bytes.length > 4 * 1024 * 1024) {
              throw const FormatException('Certificate too large');
            }
            final certificates = Directory('${directory.path}/certificates');
            await certificates.create(recursive: true);
            final file = File(
              '${certificates.path}/${sha256.convert(bytes)}.cert',
            );
            if (!await file.exists()) {
              await file.writeAsBytes(bytes, flush: true);
            }
            config = config.copyWith({'certificatePath': file.path});
          }
          await service.save(
            config,
            license: params['license'] as String?,
            password: params['password'] as String?,
            reconnect: params['reconnect'] == true,
          );
        case 'shutdown':
          if (m['source'] != 'host') throw StateError('Host only');
          await service.disconnect();
          stopping = true;
        default:
          throw const FormatException('Unknown command');
      }
      response['result'] = snapshot();
    } catch (_) {
      response['error'] = '操作未完成，请刷新状态并检查配置、文件权限或系统安全存储。';
    }
    // Mutations are never replayed after a client timeout. Cache only responses
    // for this short-lived UI session, and never cache submitted secrets.
    replies[key] = response;
    if (replies.length > 32) replies.remove(replies.keys.first);
    await writer.send(response);
    await emit();
    if (stopping) exit(0);
  }

  try {
    await writer.send({'kind': 'ready', 'version': ipcVersion, 'epoch': epoch});
    await for (final m in stdin.transform(messageDecoder)) {
      if (m['kind'] == 'vaultResult') {
        vault.receive(m);
        continue;
      }
      if (m['kind'] != 'request') continue;
      final bytes = utf8.encode(jsonEncode(m)).length;
      if (queuedRequests >= 64 || queuedBytes + bytes > 16 * 1024 * 1024) {
        // A stalled save/vault must not retain an unbounded stream of requests.
        await writer.send({
          'kind': 'response',
          'id': m['id'],
          'session': m['session'],
          'source': m['source'],
          'error': '后台操作过多，请稍后刷新状态。',
        });
        continue;
      }
      queuedRequests++;
      queuedBytes += bytes;
      tail = tail
          .then((_) => request(m))
          .whenComplete(() {
            queuedRequests--;
            queuedBytes -= bytes;
          })
          .catchError((Object _) {
            // A broken output pipe must terminate, not leave an unmanaged core.
            exit(1);
          });
    }
  } finally {
    stopping = true;
    emitTimer?.cancel();
    await service.close();
    await changes.cancel();
    await lock.close();
    // Parent EOF must release sockets even if a vault request was pending.
    exit(0);
  }
}
