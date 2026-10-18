import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/services/stasys_protocol.dart';

void main() {
  group('auth-free greeting', () {
    test('parses the READY v=2 greeting', () {
      expect(StasysProtocol.parseGreeting('READY v=2'), 2);
    });

    test('rejects legacy and unsupported greetings', () {
      // Bare READY belonged to the pre-v2 auth handshake (dead protocol).
      expect(
        () => StasysProtocol.parseGreeting('READY'),
        throwsFormatException,
      );
      expect(
        () => StasysProtocol.parseGreeting('READY v=3'),
        throwsFormatException,
      );
      // The gen= form belonged to the removed auth protocol.
      expect(
        () => StasysProtocol.parseGreeting('READY v=2 gen=7'),
        throwsFormatException,
      );
    });
  });

  group('firmware v2 sensor frame decoding', () {
    const frameHex =
        'aabb0000c03f000010c0c3f51c41cdcccc3dcdcc4cbe9a99993e9cffc800d4fe900158ab';
    final frame = Uint8List.fromList(List<int>.generate(
      36,
      (i) => int.parse(frameHex.substring(i * 2, i * 2 + 2), radix: 16),
    ));

    test('decodes firmware frame fields and XOR checksum', () {
      final packet = StasysProtocol.parseFrame(frame);
      expect(packet.ax, 1.5);
      expect(packet.ay, -2.25);
      expect(packet.az, closeTo(9.81, 0.00001));
      expect(packet.gx, closeTo(0.1, 0.00001));
      expect(packet.gy, closeTo(-0.2, 0.00001));
      expect(packet.gz, closeTo(0.3, 0.00001));
      expect(packet.magX, -100);
      expect(packet.magY, 200);
      expect(packet.magZ, -300);
      expect(packet.piezo, 400);
      expect(packet.battery, 88);
    });

    test('rejects a bad header', () {
      final invalid = Uint8List.fromList(frame)..[0] = 0;
      expect(() => StasysProtocol.parseFrame(invalid), throwsFormatException);
    });

    test('rejects frames with incorrect lengths', () {
      expect(() => StasysProtocol.parseFrame(frame.sublist(0, 35)), throwsFormatException);
      expect(
        () => StasysProtocol.parseFrame(Uint8List.fromList([...frame, 0])),
        throwsFormatException,
      );
    });

    test('rejects a bad XOR checksum', () {
      final invalid = Uint8List.fromList(frame)..[35] ^= 1;
      expect(() => StasysProtocol.parseFrame(invalid), throwsFormatException);
    });

    test('XOR covers payload bytes 2 through 34 only', () {
      final changedPayload = Uint8List.fromList(frame)..[2] ^= 1;
      expect(
        () => StasysProtocol.parseFrame(changedPayload),
        throwsFormatException,
      );

      final changedHeader = Uint8List.fromList(frame)..[0] ^= 1;
      expect(
        () => StasysProtocol.parseFrame(changedHeader),
        throwsFormatException,
      );
    });
  });

  group('LineBuffer chunked feeds', () {
    test('reassembles a greeting split across two feeds', () {
      final buffer = LineBuffer();
      expect(buffer.feed('READY v='.codeUnits), isEmpty);
      expect(buffer.feed('2\n'.codeUnits), <String>['READY v=2']);
    });

    test('reassembles an OTA text line split across two feeds', () {
      const line = 'VERSION=1.4.0';
      final buffer = LineBuffer();
      expect(buffer.feed(line.substring(0, 5).codeUnits), isEmpty);
      expect(buffer.feed('${line.substring(5)}\n'.codeUnits), <String>[line]);
    });

    test('yields complete lines from one feed, trimming CR and empties', () {
      final buffer = LineBuffer();
      expect(
        buffer.feed('READY v=2\r\n\r\nVERSION=2\n'.codeUnits),
        <String>['READY v=2', 'VERSION=2'],
      );
    });

    test('clear drops any pending partial line', () {
      final buffer = LineBuffer();
      expect(buffer.feed('OTA par'.codeUnits), isEmpty);
      buffer.clear();
      expect(buffer.feed('tial\n'.codeUnits), <String>['tial']);
      expect(buffer.text, isEmpty);
    });
  });

  group('FrameAssembler streaming', () {
    const frameHex =
        'aabb0000c03f000010c0c3f51c41cdcccc3dcdcc4cbe9a99993e9cffc800d4fe900158ab';
    Uint8List referenceFrame() => Uint8List.fromList(List<int>.generate(
          36,
          (i) => int.parse(frameHex.substring(i * 2, i * 2 + 2), radix: 16),
        ));

    test('parses a frame split at every byte boundary', () {
      final frame = referenceFrame();
      for (var split = 1; split < StasysProtocol.frameSize; split++) {
        final assembler = FrameAssembler();
        final first = assembler.feed(frame.sublist(0, split));
        expect(first.frames, isEmpty, reason: 'split at $split');
        expect(first.checksumErrors, 0, reason: 'split at $split');
        final second = assembler.feed(frame.sublist(split));
        expect(second.frames, hasLength(1), reason: 'split at $split');
        expect(second.checksumErrors, 0, reason: 'split at $split');
        expect(second.frames.single.battery, 88, reason: 'split at $split');
      }
    });

    test('parses two complete frames from one feed', () {
      final frame = referenceFrame();
      final assembler = FrameAssembler();
      final result = assembler.feed([...frame, ...frame]);
      expect(result.frames, hasLength(2));
      expect(result.checksumErrors, 0);
      expect(result.frames.every((f) => f.battery == 88), isTrue);
    });

    test('skips junk bytes before the sync header', () {
      final frame = referenceFrame();
      final assembler = FrameAssembler();
      final result = assembler.feed([0x01, 0x42, 0xaa, 0x00, 0xff, ...frame]);
      expect(result.frames, hasLength(1));
      expect(result.checksumErrors, 0);
      expect(result.frames.single.battery, 88);
    });

    test('counts a bad checksum and recovers at the next valid frame', () {
      final good = referenceFrame();
      final corrupted = Uint8List.fromList(good)..[35] ^= 0xff;
      final assembler = FrameAssembler();
      final result = assembler.feed([...corrupted, ...good]);
      expect(result.checksumErrors, 1);
      expect(result.frames, hasLength(1));
      expect(result.frames.single.battery, 88);
    });

    test('resyncs to a frame starting inside a failed candidate window', () {
      final frame = referenceFrame();
      // Fake AA BB sync + 8 junk bytes, then the real frame begins at
      // offset 10 and is cut off at the 36-byte window edge.
      final window = <int>[
        0xaa,
        0xbb,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        ...frame.sublist(0, 26),
      ];
      expect(window, hasLength(36));
      final assembler = FrameAssembler();
      final first = assembler.feed(window);
      expect(first.frames, isEmpty);
      expect(first.checksumErrors, 1);
      final second = assembler.feed(frame.sublist(26));
      expect(second.frames, hasLength(1));
      expect(second.frames.single.ax, closeTo(1.5, 1e-6));
      expect(second.frames.single.battery, 88);
      expect(second.checksumErrors, 0);
    });
  });
}
