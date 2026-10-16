import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

const maxFrameLength = 2097152;

/// Wire layout follows the official Java ProxyMessageEncoder, including serial=0.
class Frame {
  Frame(this.type, {this.serial = 0, this.info = '', List<int> data = const []})
    : data = Uint8List.fromList(data);
  final int type;
  final int serial;
  final String info;
  final Uint8List data;

  Uint8List encode() {
    final text = utf8.encode(info);
    final length = 17 + text.length + data.length;
    if (length > maxFrameLength || type < 0 || type > 255) {
      throw const FormatException('隧道消息长度或类型无效');
    }
    final bytes = Uint8List(length);
    final header = ByteData.sublistView(bytes);
    header.setUint32(0, length - 4);
    header.setUint8(4, type);
    header.setInt64(5, serial);
    header.setUint32(13, text.length);
    bytes.setRange(17, 17 + text.length, text);
    bytes.setRange(17 + text.length, length, data);
    return bytes;
  }
}

class FrameDecoder {
  Uint8List _buffer = Uint8List(4);
  int _used = 0;
  bool _body = false;

  List<Frame> add(List<int> chunk) {
    final result = <Frame>[];
    var offset = 0;
    while (offset < chunk.length) {
      final count = (_buffer.length - _used).clamp(0, chunk.length - offset);
      _buffer.setRange(_used, _used + count, chunk, offset);
      _used += count;
      offset += count;
      if (_used != _buffer.length) {
        continue;
      }
      if (!_body) {
        final size = ByteData.sublistView(_buffer).getUint32(0);
        // Check the untrusted length before allocating its body.
        if (size < 13 || size > maxFrameLength - 4) {
          throw const FormatException('隧道消息长度无效');
        }
        _buffer = Uint8List(size);
        _used = 0;
        _body = true;
      } else {
        final header = ByteData.sublistView(_buffer);
        final infoLength = header.getUint32(9);
        if (infoLength > _buffer.length - 13) {
          throw const FormatException('隧道元数据长度无效');
        }
        result.add(
          Frame(
            header.getUint8(0),
            serial: header.getInt64(1),
            info: utf8.decode(_buffer.sublist(13, 13 + infoLength)),
            data: _buffer.sublist(13 + infoLength),
          ),
        );
        _buffer = Uint8List(4);
        _used = 0;
        _body = false;
      }
    }
    return result;
  }

  void finish() {
    if (_used != 0 || _body) {
      throw const FormatException('隧道消息被截断');
    }
  }
}

final frameTransformer = StreamTransformer<Uint8List, Frame>.fromBind((
  stream,
) async* {
  final decoder = FrameDecoder();
  await for (final chunk in stream) {
    yield* Stream.fromIterable(decoder.add(chunk));
  }
  decoder.finish();
});
