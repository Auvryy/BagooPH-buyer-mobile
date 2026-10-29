import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_vault.dart';

class NativeSessionVault implements SessionVault {
  const NativeSessionVault();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
