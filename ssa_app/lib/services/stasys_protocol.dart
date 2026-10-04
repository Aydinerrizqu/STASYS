import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Parsed `READY v=2 gen=<uint32>` greeting from the v2 firmware.
class StasysGreeting {
  const StasysGreeting({required this.version, required this.generation});

  final int version;
  final int generation;
}

/// One immutable decoded 36-byte firmware v2 sensor frame.
class StasysSensorFrame {
  const StasysSensorFrame({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.magX,
    required this.magY,
    required this.magZ,
    required this.piezo,
    required this.battery,
  });

  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;
  final int magX;
  final int magY;
  final int magZ;
  final int piezo;
  final int battery;
}

/// Pure STASYS firmware v2 authentication helpers.
///
/// No Flutter dependency; never logs inputs or proofs.
class StasysProtocol {
  StasysProtocol._();

  static const int _authVersion = 2;
  static const int _nonceSize = 32;
  static const int _keySize = 32;
  static const int _identitySize = 6;
  static const int _maxUint32 = 0xffffffff;
  static const int frameSize = 36;
  static const int syncByte0 = 0xaa;
  static const int syncByte1 = 0xbb;
  static const int _checksumStart = 2;
  static const int _checksumOffset = 35;
  static final Uint8List _domain = Uint8List.fromList(
    utf8.encode('STASYS-AUTH/v2') + <int>[0],
  );

  static final RegExp _greetingPattern = RegExp(r'^READY v=(\d+) gen=(\d+)$');
  static final RegExp _hexPattern = RegExp(r'^[0-9a-fA-F]+$');

  static StasysGreeting parseGreeting(String line) {
    final match = _greetingPattern.firstMatch(line);
    if (match == null) {
      throw const FormatException('Invalid firmware greeting');
    }
    final version = int.parse(match.group(1)!);
    final generation = int.parse(match.group(2)!);
    if (version != _authVersion || generation < 0 || generation > _maxUint32) {
      throw const FormatException('Unsupported firmware greeting');
    }
    return StasysGreeting(version: version, generation: generation);
  }

  static Uint8List parseNonce(String line) {
    const prefix = 'AUTH ';
    if (!line.startsWith(prefix)) {
      throw const FormatException('Missing auth nonce');
    }
    final hex = line.substring(prefix.length);
    if (hex.length != _nonceSize * 2 || !_hexPattern.hasMatch(hex)) {
      throw const FormatException('Invalid auth nonce');
    }
    return Uint8List.fromList(
      List<int>.generate(
        _nonceSize,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }

  static String authenticationProof({
    required Uint8List key,
    required List<int> identity,
    required int generation,
    required Uint8List nonce,
  }) {
    if (key.length != _keySize) {
      throw const FormatException('Authentication key must be 32 bytes');
    }
    if (identity.length != _identitySize) {
      throw const FormatException('Identity must be 6 bytes');
    }
    if (generation < 0 || generation > _maxUint32) {
      throw const FormatException('Generation must fit in uint32');
    }
    if (nonce.length != _nonceSize) {
      throw const FormatException('Nonce must be 32 bytes');
    }
    final transcriptBytes = <int>[
      ..._domain,
      ...identity,
      generation & 0xff,
      (generation >> 8) & 0xff,
      (generation >> 16) & 0xff,
      (generation >> 24) & 0xff,
      ...nonce,
    ];
    final digest = Hmac(sha256, key).convert(transcriptBytes);
    return digest.toString();
  }

  /// Parses exactly one complete 36-byte firmware v2 sensor frame.
  ///
  /// Layout (little endian): [0..1] AA BB header, [2..25] six float32,
  /// [26..31] three int16 magnetometer, [32..33] uint16 piezo,
  /// [34] uint8 battery, [35] XOR of bytes 2..34.
  static StasysSensorFrame parseFrame(Uint8List frame) {
    if (frame.length != frameSize) {
      throw FormatException(
        'Expected $frameSize bytes, got ${frame.length}',
      );
    }
    if (frame[0] != syncByte0 || frame[1] != syncByte1) {
      throw const FormatException('Invalid packet header');
    }
    var checksum = 0;
    for (var i = _checksumStart; i < _checksumOffset; i++) {
      checksum ^= frame[i];
    }
    if (frame[_checksumOffset] != checksum) {
      throw const FormatException('Invalid packet checksum');
    }
    final data = ByteData.sublistView(frame);
    return StasysSensorFrame(
      ax: data.getFloat32(2, Endian.little),
      ay: data.getFloat32(6, Endian.little),
      az: data.getFloat32(10, Endian.little),
      gx: data.getFloat32(14, Endian.little),
      gy: data.getFloat32(18, Endian.little),
      gz: data.getFloat32(22, Endian.little),
      magX: data.getInt16(26, Endian.little),
      magY: data.getInt16(28, Endian.little),
      magZ: data.getInt16(30, Endian.little),
      piezo: data.getUint16(32, Endian.little),
      battery: data.getUint8(34),
    );
  }
}
