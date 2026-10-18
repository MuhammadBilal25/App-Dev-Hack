import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One SSE subscription to `/api/v1/stream?channels=...` (the same realtime feed the Day 1
/// match screen uses). Calls [onEvent] with each decoded `data:` payload and reconnects once
/// after a drop, so nothing polls.
class LiveChannel {
  LiveChannel({required this.baseUrl, required this.channels, required this.onEvent, required this.clientFactory});

  final String baseUrl;
  final List<String> channels;
  final void Function(Map<String, dynamic> event) onEvent;
  final http.Client Function() clientFactory;

  http.Client? _client;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  bool _closed = false;

  Future<void> open() async {
    if (_closed) return;
    _sub?.cancel();
    _client?.close();
    final client = clientFactory();
    _client = client;
    final uri = Uri.parse('$baseUrl/api/v1/stream?channels=${Uri.encodeQueryComponent(channels.join(','))}');
    try {
      final res = await client.send(http.Request('GET', uri)..headers['Accept'] = 'text/event-stream');
      if (_closed) return;
      _sub = res.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          if (!line.startsWith('data:')) return;
          try {
            onEvent(Map<String, dynamic>.from(jsonDecode(line.substring(5).trim()) as Map));
          } catch (_) {/* ignore a malformed frame */}
        },
        onDone: _reconnect,
        onError: (Object _) => _reconnect(),
        cancelOnError: true,
      );
    } on Exception {
      _reconnect();
    }
  }

  void _reconnect() {
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 5), open);
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _sub?.cancel();
    _client?.close();
  }
}
