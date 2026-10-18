import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/settings/settings.dart';

/// Read-only guest endpoints (no account needed, FR-4.2).
final guestMatchProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final r = await ref.read(apiClientProvider).get('/api/v1/guest/matches/${Uri.encodeComponent(id)}', auth: false);
  return Map<String, dynamic>.from(r as Map);
});

final guestCostreamProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final r = await ref.read(apiClientProvider).get('/api/v1/guest/costream/${Uri.encodeComponent(id)}', auth: false);
  return Map<String, dynamic>.from(r as Map);
});

final chatHistoryProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, room) async {
  final r = await ref.read(apiClientProvider).get('/api/v1/chat/${Uri.encodeComponent(room)}', auth: false);
  return ((r as Map)['messages'] as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
});

/// The server writes media URLs for its own machine (localhost). On a phone, "localhost" is the
/// phone, so the host is swapped for the host of the API the app talks to; the port stays.
String mediaUrl(String url, String serverUrl) {
  final u = Uri.tryParse(url);
  final server = Uri.tryParse(serverUrl);
  if (u == null || server == null || server.host.isEmpty) return url;
  if (u.host != 'localhost' && u.host != '127.0.0.1') return url;
  return u.replace(host: server.host).toString();
}

final serverUrlProvider = Provider<String>((ref) => ref.watch(settingsProvider.select((s) => s.serverUrl)));
