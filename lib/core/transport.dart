import 'dart:async';
import 'dart:io';

import 'config.dart';
import 'protocol.dart';

class Cancelled implements Exception {
  const Cancelled();
}

/// All resources belong to one connection generation. Late dial results are
/// closed here, so clicking disconnect cannot resurrect a superseded session.
class ConnectionScope {
  bool closed = false;
  final done = Completer<void>();
  final sockets = <Socket>{};
  final pending = <ConnectionTask<Socket>>{};
  final cleanups = <void Function()>[];
  final _operations = <void Function()>{};
  int get pendingOperationCount => _operations.length;
  Future<T> wait<T>(Future<T> operation) {
    final result = Completer<T>();
    void cancel() {
      if (!result.isCompleted) result.completeError(const Cancelled());
    }

    if (closed) {
      cancel();
    } else {
      _operations.add(cancel);
    }
    // Future.any with done.future retains one listener for every completed UDP
    // lookup until disconnect. Remove each cancellation registration as soon as
    // its operation settles; still observe late failures after cancellation.
    operation.then<void>(
      (value) {
        _operations.remove(cancel);
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        _operations.remove(cancel);
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }

  Future<Socket> dial(
    String host,
    int port, {
    SecurityContext? security,
  }) async {
    if (closed) {
      throw const Cancelled();
    }
    final task = await wait(
      Socket.startConnect(host, port)
          .then((task) {
            if (closed) {
              task.cancel();
              throw const Cancelled();
            }
            pending.add(task);
            return task;
          })
          .timeout(const Duration(seconds: 10)),
    );
    Socket? socket;
    try {
      socket = await wait(
        task.socket
            .then((value) {
              if (closed) {
                value.destroy();
                throw const Cancelled();
              }
              sockets.add(value);
              return value;
            })
            .timeout(const Duration(seconds: 10)),
      );
      socket!.setOption(SocketOption.tcpNoDelay, true);
      if (security != null) {
        final plain = socket;
        socket = await wait(
          SecureSocket.secure(plain, host: host, context: security)
              .then((secure) {
                if (closed) {
                  secure.destroy();
                  throw const Cancelled();
                }
                sockets.remove(plain);
                sockets.add(secure);
                return secure;
              })
              .timeout(const Duration(seconds: 10)),
        );
      }
      // Observe sink failures even before a reader or writer starts.
      socket.done.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return socket;
    } catch (_) {
      socket?.destroy();
      rethrow;
    } finally {
      pending.remove(task);
      task.cancel();
    }
  }

  void release(Socket? socket) {
    if (socket != null) {
      sockets.remove(socket);
      socket.destroy();
    }
  }

  void close() {
    if (closed) {
      return;
    }
    closed = true;
    for (final cancel in _operations.toList()) {
      cancel();
    }
    _operations.clear();
    // Socket destruction can synchronously resume a forwarding task, whose
    // finally block releases its socket. Iterate snapshots during teardown.
    for (final task in pending.toList()) {
      task.cancel();
    }
    pending.clear();
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    sockets.clear();
    for (final cleanup in cleanups.toList()) {
      cleanup();
    }
    cleanups.clear();
    done.complete();
  }
}

class Wire {
  Wire(this.socket, this.config) {
    frames = socket.transform(frameTransformer);
    socket.done.then<void>(
      (_) {
        close();
      },
      onError: (Object _, StackTrace _) {
        close();
      },
    );
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = _clock.elapsedMilliseconds;
      if (config.readIdleSeconds > 0 &&
              now - _readAt >= config.readIdleSeconds * 1000 ||
          config.allIdleSeconds > 0 &&
              now - _lastActivity >= config.allIdleSeconds * 1000) {
        close();
        return;
      }
      if (config.heartbeatSeconds > 0 &&
          now - _writeAt >= config.heartbeatSeconds * 1000 &&
          _pendingBytes == 0) {
        unawaited(
          send(Frame(1)).catchError((Object _) {
            close();
          }),
        );
      }
    });
  }
  final Socket socket;
  final ClientConfig config;
  late final Stream<Frame> frames;
  final _clock = Stopwatch();
  late final Timer _timer;
  int _readAt = 0, _writeAt = 0, _pendingBytes = 0;
  bool _closed = false;
  Future<void> _tail = Future.value();
  int get _lastActivity => _readAt > _writeAt ? _readAt : _writeAt;
  void received() {
    _readAt = _clock.elapsedMilliseconds;
  }

  Future<void> send(Frame frame) {
    final bytes = frame.encode();
    if (_closed) {
      return Future.error(const SocketException('隧道已关闭'));
    }
    if (_pendingBytes + bytes.length > 4 * 1024 * 1024) {
      close();
      return Future.error(const SocketException('隧道写队列已满'));
    }
    _pendingBytes += bytes.length;
    final operation = _tail
        .then((_) async {
          if (_closed) {
            throw const SocketException('隧道已关闭');
          }
          socket.add(bytes);
          await socket.flush();
          _writeAt = _clock.elapsedMilliseconds;
        })
        .whenComplete(() => _pendingBytes -= bytes.length);
    _tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        close();
      },
    );
    return operation;
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _timer.cancel();
    socket.destroy();
  }
}
