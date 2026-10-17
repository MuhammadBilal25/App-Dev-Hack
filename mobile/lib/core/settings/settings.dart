import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` with the instance loaded before `runApp`.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('sharedPrefsProvider not overridden'));

const defaultServerUrl = 'http://localhost:8080';

class AppSettings {
  const AppSettings({required this.serverUrl, required this.themeMode, this.lastTenantId});

  final String serverUrl;
  final ThemeMode themeMode;

  /// Tenant of the last signed-in user, so the login screen can show its logo and colour.
  final String? lastTenantId;

  AppSettings copyWith({String? serverUrl, ThemeMode? themeMode, String? lastTenantId}) => AppSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        themeMode: themeMode ?? this.themeMode,
        lastTenantId: lastTenantId ?? this.lastTenantId,
      );
}

/// Returns a cleaned server URL, or null when [input] is not an http(s) address.
String? normalizeServerUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return null;
  return s;
}

class SettingsController extends Notifier<AppSettings> {
  static const _kServer = 'server_url';
  static const _kTheme = 'theme_mode';
  static const _kTenant = 'last_tenant_id';
  static const _kDevice = 'device_id';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return AppSettings(
      serverUrl: prefs.getString(_kServer) ?? defaultServerUrl,
      themeMode: ThemeMode.values.firstWhere((m) => m.name == prefs.getString(_kTheme), orElse: () => ThemeMode.system),
      lastTenantId: prefs.getString(_kTenant),
    );
  }

  /// Saves the server address. Returns false (and saves nothing) when it is not a valid URL.
  Future<bool> setServerUrl(String input) async {
    final url = normalizeServerUrl(input);
    if (url == null) return false;
    await _prefs.setString(_kServer, url);
    state = state.copyWith(serverUrl: url);
    return true;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_kTheme, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setLastTenant(String? tenantId) async {
    if (tenantId == null) return;
    await _prefs.setString(_kTenant, tenantId);
    state = state.copyWith(lastTenantId: tenantId);
  }

  /// Stable id of this install, sent with offline sync batches.
  String deviceId() {
    final existing = _prefs.getString(_kDevice);
    if (existing != null) return existing;
    final r = Random.secure();
    final id = 'device-${List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join()}';
    _prefs.setString(_kDevice, id);
    return id;
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
