import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Overridden in `main()` with the box opened before `runApp`.
final cacheBoxProvider = Provider<Box<String>>((ref) => throw UnimplementedError('cacheBoxProvider not overridden'));

const cacheBoxName = 'api_cache';

/// A response plus whether it came from the offline cache.
class Cached<T> {
  const Cached(this.data, {this.fromCache = false});

  final T data;
  final bool fromCache;
}

/// GET with an offline fallback: successful responses are stored in Hive, and when the server
/// can't be reached the last stored copy is returned so Fixtures, Standings and Club open offline.
Future<Cached<Map<String, dynamic>>> cachedGet(Ref ref, String path) async {
  final box = ref.read(cacheBoxProvider);
  try {
    final body = await ref.read(apiClientProvider).get(path) as Map<String, dynamic>;
    // Hive updates its in-memory copy at once; the disk write needn't hold up the screen.
    unawaited(box.put(path, jsonEncode(body)));
    return Cached(body);
  } on ApiException catch (e) {
    final hit = box.get(path);
    if (e.isNetwork && hit != null) return Cached(jsonDecode(hit) as Map<String, dynamic>, fromCache: true);
    rethrow;
  }
}
