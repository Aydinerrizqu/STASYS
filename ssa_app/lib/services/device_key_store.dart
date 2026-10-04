import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _deviceKeyName = 'stasys_device_key_v2';

abstract interface class DeviceKeyBackend {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class _SecureStorageDeviceKeyBackend implements DeviceKeyBackend {
  const _SecureStorageDeviceKeyBackend(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _deviceKeyName);

  @override
  Future<void> write(String value) =>
      _storage.write(key: _deviceKeyName, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _deviceKeyName);
}

class DeviceKeyStore {
  DeviceKeyStore({DeviceKeyBackend? backend})
      : _backend = backend ??
            const _SecureStorageDeviceKeyBackend(FlutterSecureStorage());

  final DeviceKeyBackend _backend;

  Future<Uint8List?> readKey() async {
    final hex = await _backend.read();
    return hex == null ? null : parseHexKey(hex);
  }

  Future<void> saveKey(String hex) async {
    final key = parseHexKey(hex);
    await _backend.write(_encodeHex(key));
  }

  Future<void> deleteKey() => _backend.delete();

  static Uint8List parseHexKey(String hex) {
    if (hex.length != 64 || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw const FormatException('Device key must be exactly 64 hex characters.');
    }

    return Uint8List.fromList(List<int>.generate(
      32,
      (index) => int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
    ));
  }

  static String _encodeHex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
