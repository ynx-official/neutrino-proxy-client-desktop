import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/core/transport.dart';

void main() {
  test(
    'completed packet operations release cancellation registrations',
    () async {
      final scope = ConnectionScope();
      for (var i = 0; i < 10000; i++) {
        expect(await scope.wait(Future.value(i)), i);
      }
      expect(scope.pendingOperationCount, 0);
      final pending = Completer<int>();
      final canceled = expectLater(
        scope.wait(pending.future),
        throwsA(isA<Cancelled>()),
      );
      expect(scope.pendingOperationCount, 1);
      scope.close();
      await canceled;
      expect(scope.pendingOperationCount, 0);
      // A late failure must still be observed after cancellation.
      pending.completeError(StateError('late synthetic operation'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'operation errors release registrations and closed scopes reject new work',
    () async {
      final scope = ConnectionScope();
      await expectLater(
        scope.wait(Future<int>.error(StateError('synthetic'))),
        throwsStateError,
      );
      expect(scope.pendingOperationCount, 0);
      scope.close();
      await expectLater(scope.wait(Future.value(1)), throwsA(isA<Cancelled>()));
      expect(scope.pendingOperationCount, 0);
    },
  );
}
