import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../copy/error_messages.dart';
import '../theme/status_colors.dart';
import '../theme/tokens.dart';
import 'error_banner.dart';
import 'skeleton.dart';

/// Plain-language message for any error thrown by a provider.
String errorText(Object e) => e is ApiException ? e.message : genericErrorMessage;

/// Loading → skeleton, error → ErrorBanner with Retry, data → [builder]. While refreshing, the
/// previous data stays on screen.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, required this.onRetry, this.skeletonRows = 5, this.id = 'async'});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  final int skeletonRows;
  final String id;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) return ErrorBanner(id: '${id}_error', message: errorText(value.error!), onRetry: onRetry);
    return Skeleton(rows: skeletonRows);
  }
}

/// Small notice shown when a screen is showing the offline copy.
class CachedNotice extends StatelessWidget {
  const CachedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.status.warning;
    return Semantics(
      identifier: 'cached_notice',
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            Icon(Icons.history, size: 18, color: c.fg),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                "You're offline. Showing the last saved copy.",
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: c.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
