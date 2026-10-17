import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'user.dart';

/// Keeps the JWT (and the last user profile, so the app opens offline) in secure storage, with an
/// in-memory copy for request headers.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _kToken = 'jwt';
  static const _kUser = 'user';

  String? _token;
  String? get token => _token;

  Future<String?> load() async {
    try {
      _token = await _storage.read(key: _kToken);
    } on Exception {
      _token = null;
    }
    return _token;
  }

  Future<AppUser?> loadUser() async {
    try {
      final raw = await _storage.read(key: _kUser);
      if (raw == null) return null;
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  Future<void> save(String token, AppUser user) async {
    _token = token;
    await _storage.write(key: _kToken, value: token);
    await saveUser(user);
  }

  Future<void> saveUser(AppUser user) => _storage.write(key: _kUser, value: jsonEncode(user.toJson()));

  Future<void> clear() async {
    _token = null;
    try {
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kUser);
    } on Exception {
      // Nothing stored; the in-memory token is already gone.
    }
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
