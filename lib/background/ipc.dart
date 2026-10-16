import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

const ipcVersion = 1;
// Allows one bounded 4 MiB certificate (base64) without an unbounded stream.
const maxMessageBytes = 8 * 1024 * 1024;

Uint8List encodeMessage(Map<String, dynamic> message) {
  final body = utf8.encode(jsonEncode(message));
  if (body.length > maxMessageBytes) {
    throw const FormatException('IPC message too large');
  }
  final result = Uint8List(body.length + 4);
  ByteData.sublistView(result).setUint32(0, body.length);
  result.setRange(4, result.length, body);
  return result;
}

final messageDecoder =
    StreamTransformer<List<int>, Map<String, dynamic>>.fromBind((input) {
      final header = Uint8List(4);
      var headerUsed = 0, bodyUsed = 0;
      Uint8List? body;
      // A synchronous transformer lets cancellation close the pipe immediately.
      // An async* decoder can wait for the next input after detach, keeping an
      // otherwise finished Flutter process alive while the host is quiet.
      return input.transform(
        StreamTransformer<List<int>, Map<String, dynamic>>.fromHandlers(
          handleData: (chunk, sink) {
            var offset = 0;
            while (offset < chunk.length) {
              if (body == null) {
                final count = (4 - headerUsed).clamp(0, chunk.length - offset);
                header.setRange(headerUsed, headerUsed + count, chunk, offset);
                headerUsed += count;
                offset += count;
                if (headerUsed < 4) continue;
                final length = ByteData.sublistView(header).getUint32(0);
                if (length == 0 || length > maxMessageBytes) {
                  throw const FormatException('Invalid IPC length');
                }
                body = Uint8List(length);
                bodyUsed = 0;
              }
              final current = body!;
              final count = (current.length - bodyUsed).clamp(
                0,
                chunk.length - offset,
              );
              current.setRange(bodyUsed, bodyUsed + count, chunk, offset);
              offset += count;
              bodyUsed += count;
              if (bodyUsed == current.length) {
                final decoded = jsonDecode(utf8.decode(current));
                if (decoded is! Map<String, dynamic>) {
                  throw const FormatException('Invalid IPC object');
                }
                sink.add(decoded);
                body = null;
                headerUsed = 0;
              }
            }
          },
          handleDone: (sink) {
            if (headerUsed != 0 || body != null) {
              sink.addError(const FormatException('Truncated IPC frame'));
            }
            sink.close();
          },
        ),
      );
    });

/// Bound queued output, including when the other process stops consuming data.
class MessageWriter {
  MessageWriter(this.sink);
  final StreamSink<List<int>> sink;
  Future<void> _tail = Future.value();
  int _queued = 0;
  bool _closed = false;
  Future<void> send(Map<String, dynamic> message) {
    if (_closed) return Future.error(StateError('IPC closed'));
    final bytes = encodeMessage(message);
    if (_queued + bytes.length > 16 * 1024 * 1024) {
      return Future.error(StateError('IPC queue full'));
    }
    _queued += bytes.length;
    final task = _tail.then((_) => sink.addStream(Stream.value(bytes)));
    _tail = task
        .whenComplete(() => _queued -= bytes.length)
        .catchError((Object _) {});
    return task;
  }

  Future<void> close() async {
    _closed = true;
    await _tail;
    await sink.close();
  }
}
