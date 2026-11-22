import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'stasys_auth_config.dart';

/// Parsed `AUTH <nonce-hex> <mac-hex>` challenge (protocol v3).
class StasysAuthChallenge {
  const StasysAuthChallenge({required this.nonce, required this.mac});

  final Uint8List nonce;
  final Uint8List mac;
}

/// One immutable decoded 36-byte firmware sensor frame.
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

/// Incrementally collects newline-delimited text from arbitrary byte chunks.
class LineBuffer {
  String _text = '';

  String get text => _text;

  List<String> feed(List<int> bytes) {
    _text += String.fromCharCodes(bytes);
    final lines = <String>[];
    var newline = _text.indexOf('\n');
    while (newline >= 0) {
      final line = _text.substring(0, newline).trim();
      if (line.isNotEmpty) lines.add(line);
      _text = _text.substring(newline + 1);
      newline = _text.indexOf('\n');
    }
    return lines;
  }

  void clear() => _text = '';
}

class FrameAssemblyResult {
  const FrameAssemblyResult({required this.frames, required this.checksumErrors});

  final List<StasysSensorFrame> frames;
  final int checksumErrors;
}

/// Incrementally frames sensor data and recovers from corrupt candidates.
class FrameAssembler {
  final List<int> _buffer = [];

  FrameAssemblyResult feed(List<int> bytes) {
    _buffer.addAll(bytes);
    final frames = <StasysSensorFrame>[];
    var errors = 0;
    while (true) {
      var header = -1;
      for (var i = 0; i + 1 < _buffer.length; i++) {
        if (_buffer[i] == StasysProtocol.syncByte0 &&
            _buffer[i + 1] == StasysProtocol.syncByte1) {
          header = i;
          break;
        }
      }
      if (header < 0) {
        final keepSyncPrefix =
            _buffer.isNotEmpty && _buffer.last == StasysProtocol.syncByte0;
        _buffer
          ..clear()
          ..addAll(keepSyncPrefix ? [StasysProtocol.syncByte0] : const []);
        break;
      }
      if (header > 0) _buffer.removeRange(0, header);
      if (_buffer.length < StasysProtocol.frameSize) break;
      try {
        frames.add(StasysProtocol.parseFrame(
          Uint8List.fromList(_buffer.sublist(0, StasysProtocol.frameSize)),
        ));
        _buffer.removeRange(0, StasysProtocol.frameSize);
      } on FormatException {
        errors++;
        _buffer.removeAt(0);
      }
    }
    return FrameAssemblyResult(frames: frames, checksumErrors: errors);
  }

  void clear() => _buffer.clear();
}

/// Pure STASYS wire protocol helpers (greeting, auth v3, 36-byte frames).
class StasysProtocol {
  StasysProtocol._();

  static const int authVersion = 3;
  static const int legacyAuthFreeVersion = 2;
  static const int authNonceSize = 32;
  static const int authMacSize = 6;
  static const int authProofSize = 32;
  static const int frameSize = 36;
  static const int syncByte0 = 0xaa;
  static const int syncByte1 = 0xbb;
  static const int _checksumStart = 2;
  static const int _checksumOffset = 35;
  static const String _authDomain = 'STASYS-AUTH/v3';

  static final RegExp _greetingPattern = RegExp(r'^READY v=(\d+)$');
  static final RegExp _challengePattern =
      RegExp(r'^AUTH ([0-9a-fA-F]{64}) ([0-9a-fA-F]{12})$');
  static final RegExp _hexPattern = RegExp(r'^[0-9a-fA-F]+$');

  /// Returns protocol version from `READY v=N`. Supports v2 (auth-free) and v3.
  static int parseGreeting(String line) {
    final match = _greetingPattern.firstMatch(line);
    if (match == null) {
      throw const FormatException('Invalid firmware greeting');
    }
    final version = int.parse(match.group(1)!);
    if (version != legacyAuthFreeVersion && version != authVersion) {
      throw const FormatException('Unsupported firmware greeting');
    }
    return version;
  }

  static StasysAuthChallenge parseAuthChallenge(String line) {
    final match = _challengePattern.firstMatch(line);
    if (match == null) {
      throw const FormatException('Invalid AUTH challenge');
    }
    return StasysAuthChallenge(
      nonce: _decodeHex(match.group(1)!, authNonceSize),
      mac: _decodeHex(match.group(2)!, authMacSize),
    );
  }

  /// Builds `PROOF <64-hex-hmac>\n` using the development SALT unless overridden.
  static String buildProofLine(StasysAuthChallenge challenge, {List<int>? salt}) {
    final saltBytes = Uint8List.fromList(salt ?? stasysAuthSalt);
    if (saltBytes.length != authNonceSize) {
      throw const FormatException('SALT must be 32 bytes');
    }
    final deviceKey = _deriveDeviceKey(saltBytes, challenge.mac);
    final transcript = _buildTranscript(challenge.mac, challenge.nonce);
    final proof = Hmac(sha256, deviceKey).convert(transcript).bytes;
    return 'PROOF ${proof.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\n';
  }

  static Uint8List _deriveDeviceKey(Uint8List salt, Uint8List mac) {
    return Uint8List.fromList(Hmac(sha256, salt).convert(mac).bytes);
  }

  static Uint8List _buildTranscript(Uint8List mac, Uint8List nonce) {
    if (mac.length != authMacSize || nonce.length != authNonceSize) {
      throw const FormatException('Invalid challenge sizes');
    }
    return Uint8List.fromList([
      ...utf8.encode(_authDomain),
      ...mac,
      ...nonce,
    ]);
  }

  static Uint8List _decodeHex(String hex, int outLen) {
    if (hex.length != outLen * 2 || !_hexPattern.hasMatch(hex)) {
      throw const FormatException('Invalid hex field');
    }
    return Uint8List.fromList(
      List<int>.generate(
        outLen,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }

  /// Parses exactly one complete 36-byte sensor frame.
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
