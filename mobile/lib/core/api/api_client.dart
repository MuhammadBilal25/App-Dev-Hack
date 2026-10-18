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

  Future<dynamic> patch(String path, {Object? body}) => send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => send('DELETE', path);

  /// Uploads raw bytes (an image) with its content type, reporting progress from 0 to 1 as the
  /// body is streamed. Errors map to plain-language [ApiException]s like every other call.
  Future<dynamic> upload(String path, List<int> bytes, String contentType, {void Function(double)? onProgress}) async {
    final req = http.StreamedRequest('POST', Uri.parse('$baseUrl$path'));
    req.headers['Accept'] = 'application/json';
    req.headers['Content-Type'] = contentType;
    req.contentLength = bytes.length;
    final token = tokens.token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    final future = _http.send(req).timeout(const Duration(seconds: 60));
    const chunk = 32 * 1024;
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = i + chunk < bytes.length ? i + chunk : bytes.length;
      req.sink.add(bytes.sublist(i, end));
      onProgress?.call(end / bytes.length);
      await Future<void>.delayed(Duration.zero);
    }
    unawaited(req.sink.close());
    final http.Response res;
    try {
      res = await http.Response.fromStream(await future);
    } on Exception {
      onReachability(false);
      throw const ApiException.network();
    }
    onReachability(true);
    return _handle(res, token);
  }

  /// GET returning raw bytes (the PDF receipt).
  Future<List<int>> getBytes(String path) async {
    final req = http.Request('GET', Uri.parse('$baseUrl$path'));
    final token = tokens.token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
    } on Exception {
      onReachability(false);
      throw const ApiException.network();
    }
    onReachability(true);
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    _handle(res, token);
    return const [];
  }

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
    return _handle(res, auth ? token : null);
  }

  dynamic _handle(http.Response res, String? token) {
    final decoded = _decode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final error = decoded is Map && decoded['error'] is Map ? decoded['error'] as Map : const {};
    final code = error['code'] is String ? error['code'] as String : 'HTTP_${res.statusCode}';
    final details = error['details'];
    final fields = details is Map && details['fields'] is List ? (details['fields'] as List).whereType<String>().toList() : const <String>[];
    if (res.statusCode == 401 && token != null) onUnauthorized();
    throw ApiException(
      code: code,
      status: res.statusCode,
      message: messageFor(code, status: res.statusCode),
      fields: fields,
      details: details is Map<String, dynamic> ? details : const {},
    );
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
