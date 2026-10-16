import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/background/client.dart';
import 'package:neutrino_proxy_client_desktop/background/ipc.dart';

class BlockedSink implements StreamSink<List<int>> {
  final blocked = Completer<void>();
  @override
  Future<void> addStream(Stream<List<int>> stream) => blocked.future;
  @override
  void add(List<int> data) => throw UnimplementedError();
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw UnimplementedError();
  @override
  Future<void> get done => blocked.future;
  @override
  Future<void> close() {
    if (!blocked.isCompleted) blocked.complete();
    return blocked.future;
  }
}

void main() {
  test(
    'host EOF interrupts a request even while its write is blocked',
    () async {
      final input = StreamController<List<int>>();
      final output = BlockedSink();
      final client = ProcessClientBackend(input.stream, output);
      addTearDown(() async {
        await output.close();
        await client.close();
      });
      final failure = expectLater(
        client.initialize().timeout(const Duration(seconds: 1)),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      await input.close();
      await failure;
    },
  );
  test(
    'UI snapshots reject stale revisions and detach never sends shutdown',
    () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final operations = <String>[];
      final client = ProcessClientBackend(input.stream, output.sink);
      final messages = output.stream.transform(messageDecoder).listen((
        message,
      ) {
        operations.add(message['op'] as String);
        input.add(
          encodeMessage({
            'kind': 'response',
            'id': message['id'],
            'result': {'epoch': 'worker-one', 'revision': 5, 'ready': true},
          }),
        );
      });
      await client.initialize();
      input.add(
        encodeMessage({
          'kind': 'state',
          'data': {'epoch': 'worker-one', 'revision': 3, 'ready': false},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.snapshot['revision'], 5);
      input.add(
        encodeMessage({
          'kind': 'state',
          'data': {'epoch': 'worker-two', 'revision': 1, 'ready': true},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.snapshot['epoch'], 'worker-two');
      await client.close().timeout(const Duration(seconds: 3));
      expect(operations, ['attach', 'detach']);
      await input.close();
      await messages.cancel();
    },
  );

  test(
    'host EOF fails a pending request and makes the UI unavailable',
    () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final client = ProcessClientBackend(input.stream, output.sink);
      final messages = output.stream.listen((_) {});
      final initialize = client.initialize();
      final failure = expectLater(initialize, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await input.close();
      await failure;
      expect(client.snapshot['ready'], false);
      expect(client.snapshot['error'], isNotEmpty);
      await client.close().timeout(const Duration(seconds: 3));
      await messages.cancel();
    },
  );
}
