import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neutrino_proxy_client_desktop/core/protocol.dart';

void main() {
  test('AUTH matches the official Java encoder and zero default serial', () {
    expect(Frame(2, info: 'k,id').encode(), [
      0,
      0,
      0,
      17,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      4,
      107,
      44,
      105,
      100,
    ]);
  });
  test(
    'incremental decoder handles every split, coalesced frames and UTF-8',
    () {
      final first = Frame(
        5,
        serial: -42,
        info: '访客',
        data: [0, 255, 3],
      ).encode();
      final second = Frame(1).encode();
      for (var split = 0; split <= first.length; split++) {
        final decoder = FrameDecoder();
        final result = [
          ...decoder.add(first.sublist(0, split)),
          ...decoder.add([...first.sublist(split), ...second]),
        ];
        expect(result, hasLength(2));
        expect(result[0].serial, -42);
        expect(result[0].info, '访客');
        expect(result[0].data, [0, 255, 3]);
        expect(result[1].type, 1);
      }
    },
  );
  test('reject lengths before allocating attacker supplied sizes', () {
    for (final size in [0, 12, maxFrameLength - 3, 0x7fffffff, 0xffffffff]) {
      final header = ByteData(4)..setUint32(0, size);
      expect(
        () => FrameDecoder().add(header.buffer.asUint8List()),
        throwsFormatException,
      );
    }
    final invalid = Frame(1).encode();
    ByteData.sublistView(invalid).setUint32(13, 1);
    expect(() => FrameDecoder().add(invalid), throwsFormatException);
  });
  test(
    'complete frame limit includes four-byte prefix; unknown type survives',
    () {
      final limit = Frame(127, data: Uint8List(maxFrameLength - 17)).encode();
      expect(limit.length, maxFrameLength);
      expect(FrameDecoder().add(limit).single.type, 127);
      expect(
        () => Frame(5, data: Uint8List(maxFrameLength - 16)).encode(),
        throwsFormatException,
      );
    },
  );
  test('truncated stream and malformed UTF-8 are rejected', () {
    final decoder = FrameDecoder()..add([0, 0, 0]);
    expect(decoder.finish, throwsFormatException);
    final invalid = Frame(2, info: 'a').encode()..last = 255;
    expect(() => FrameDecoder().add(invalid), throwsFormatException);
    expect(
      utf8.decode(
        FrameDecoder().add(Frame(5, data: [65]).encode()).single.data,
      ),
      'A',
    );
  });
}
