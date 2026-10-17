import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_controller.dart';
import '../auth/token_store.dart';
import '../connectivity/connectivity.dart';
import '../copy/error_messages.dart';
import '../settings/settings.dart';
import 'api_exception.dart';

/// Thin JSON client for the backend. Adds the bearer token, maps `error.code` to a plain-language
/// [ApiException], reports whether the server was reachable, and signs out on 401.
///
/// `/api/v1` is rate limited (100 requests per 10 s), so the app never polls: it fetches on
/// screen open, on pull-to-refresh and when realtime events arrive.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokens,
    required this.onUnauthorized,
    required this.onReachability,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final void Function() onUnauthorized;
  final void Function(bool reachable) onReachability;
  final http.Client _http;

  static const timeout = Duration(seconds: 15);

  Future<dynamic> get(String path, {bool auth = true}) => send('GET', path, auth: auth);

  Future<dynamic> post(String path, {Object? body, bool auth = true}) => send('POST', path, body: body, auth: auth);

  Future<dynamic> send(String method, String path, {Object? body, bool auth = true}) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final token = tokens.token;
    if (auth && token != null) req.headers['Authorization'] = 'Bearer $token';

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
    } on Exception {
      onReachability(false);
      throw const ApiException.network();
    }
    onReachability(true);

    final decoded = _decode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final error = decoded is Map && decoded['error'] is Map ? decoded['error'] as Map : const {};
    final code = error['code'] is String ? error['code'] as String : 'HTTP_${res.statusCode}';
    final details = error['details'];
    final fields = details is Map && details['fields'] is List ? (details['fields'] as List).whereType<String>().toList() : const <String>[];
    if (res.statusCode == 401 && auth && token != null) onUnauthorized();
    throw ApiException(code: code, status: res.statusCode, message: messageFor(code, status: res.statusCode), fields: fields);
  }

  /// One cheap reachability check, used when the device reconnects (not on a timer).
  Future<bool> ping() async {
    try {
      await get('/api/v1/ping', auth: false);
      return true;
    } on ApiException catch (e) {
      return !e.isNetwork;
    }
  }

  static dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: ref.watch(settingsProvider.select((s) => s.serverUrl)),
    tokens: ref.watch(tokenStoreProvider),
    client: ref.watch(httpClientProvider),
    onUnauthorized: () => ref.read(authControllerProvider.notifier).handleUnauthorized(),
    onReachability: (ok) => ref.read(serverReachableProvider.notifier).set(ok),
  );
});
