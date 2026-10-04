import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Parsed `READY v=2 gen=<uint32>` greeting from the v2 firmware.
class StasysGreeting {
  const StasysGreeting({required this.version, required this.generation});

  final int version;
  final int generation;
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
}
