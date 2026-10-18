import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';

/// Absolute URL for a server path such as `/media/products/...` (uploads are served by the API).
String mediaUrl(String serverUrl, String path) => path.startsWith('http') ? path : '$serverUrl$path';

/// An uploaded image (product photo, club or tenant logo) loaded from the server, with the
/// [fallback] shown while loading, when there is no image, and when it can't be fetched (offline).
class RemoteImage extends ConsumerWidget {
  const RemoteImage({super.key, required this.path, required this.fallback, this.fit = BoxFit.cover, this.semanticLabel});

  final String? path;
  final Widget fallback;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = path;
    if (p == null || p.isEmpty) return fallback;
    final base = ref.watch(settingsProvider.select((s) => s.serverUrl));
    return Image.network(
      mediaUrl(base, p),
      fit: fit,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      loadingBuilder: (context, child, progress) => progress == null ? child : fallback,
      errorBuilder: (context, error, stack) => fallback,
    );
  }
}
