import 'dart:typed_data';


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

/// Incrementally frames v2 sensor data and recovers from corrupt candidates.
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
        final keepSyncPrefix = _buffer.isNotEmpty &&
            _buffer.last == StasysProtocol.syncByte0;
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

/// Pure STASYS firmware v2 protocol helpers.
class StasysProtocol {
  StasysProtocol._();

  static const int frameSize = 36;
  static const int syncByte0 = 0xaa;
  static const int syncByte1 = 0xbb;
  static const int _checksumStart = 2;
  static const int _checksumOffset = 35;
  /// Parses the auth-free firmware greeting: exactly `READY v=2`.
  ///
  /// Returns the firmware protocol version. The bare `READY` greeting and
  /// the `READY v=2 gen=<n>` form belonged to the removed auth protocol.
  static int parseGreeting(String line) {
    final match = RegExp(r'^READY v=(\d+)$').firstMatch(line);
    if (match == null) {
      throw const FormatException('Invalid firmware greeting');
    }
    final version = int.parse(match.group(1)!);
    if (version != 2) {
      throw const FormatException('Unsupported firmware greeting');
    }
    return version;
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
