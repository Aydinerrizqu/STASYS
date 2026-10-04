import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/services/stasys_protocol.dart';

void main() {
  group('v2 authentication proof', () {
    final identity = <int>[0x78, 0x1c, 0x3c, 0xf5, 0x16, 0x18];
    final nonce = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final key = Uint8List.fromList([
      0x01,
      0x23,
      0x45,
      0x67,
      0x89,
      0xab,
      0xcd,
      0xef,
      0xfe,
      0xdc,
      0xba,
      0x98,
      0x76,
      0x54,
      0x32,
      0x10,
      0x01,
      0x23,
      0x45,
      0x67,
      0x89,
      0xab,
      0xcd,
      0xef,
      0xfe,
      0xdc,
      0xba,
      0x98,
      0x76,
      0x54,
      0x32,
      0x10,
    ]);

    test('matches the firmware Python HMAC vector', () {
      final proof = StasysProtocol.authenticationProof(
        key: key,
        identity: identity,
        generation: 7,
        nonce: nonce,
      );
      expect(
        proof,
        'afb667996e895d54a1c77f26ab66f46e5bbb63c509194eeec1b76e6b18cb5678',
      );
    });

    test('parses a supported v2 greeting', () {
      final greeting = StasysProtocol.parseGreeting('READY v=2 gen=7');
      expect(greeting.version, 2);
      expect(greeting.generation, 7);
    });

    test('rejects legacy and unsupported greetings', () {
      expect(
        () => StasysProtocol.parseGreeting('READY'),
        throwsFormatException,
      );
      expect(
        () => StasysProtocol.parseGreeting('READY v=3 gen=7'),
        throwsFormatException,
      );
    });

    test('rejects negative or out-of-range greeting generations', () {
      expect(
        () => StasysProtocol.parseGreeting('READY v=2 gen=-1'),
        throwsFormatException,
      );
      expect(
        () => StasysProtocol.parseGreeting('READY v=2 gen=4294967296'),
        throwsFormatException,
      );
    });

    test('parses a 32-byte AUTH nonce', () {
      final nonceHex = nonce
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(StasysProtocol.parseNonce('AUTH $nonceHex'), nonce);
    });

    test('rejects malformed AUTH nonce prefix, length, and hex', () {
      final validNonceHex = nonce
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(
        () => StasysProtocol.parseNonce('AUTHX $validNonceHex'),
        throwsFormatException,
      );
      expect(() => StasysProtocol.parseNonce('AUTH 00'), throwsFormatException);
      expect(
        () => StasysProtocol.parseNonce('AUTH ${'g' * 64}'),
        throwsFormatException,
      );
    });

    test('rejects invalid authentication input lengths and ranges', () {
      expect(
        () => StasysProtocol.authenticationProof(
          key: Uint8List(31),
          identity: identity,
          generation: 7,
          nonce: nonce,
        ),
        throwsFormatException,
      );
      expect(
        () => StasysProtocol.authenticationProof(
          key: key,
          identity: identity,
          generation: 0x100000000,
          nonce: nonce,
        ),
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

}
