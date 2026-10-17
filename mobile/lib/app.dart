import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_client.dart';
import 'core/connectivity/connectivity.dart';
import 'core/router/router.dart';
import 'core/settings/settings.dart';
import 'core/sync/sync_queue.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_providers.dart';

class HuddleApp extends ConsumerWidget {
  const HuddleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantBrandProvider);
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final router = ref.watch(routerProvider);

    // When the device gets a network back, check the server once (no polling).
    ref.listen<AsyncValue<bool>>(deviceOnlineProvider, (prev, next) {
      if (next.value == true && prev?.value != true) ref.read(apiClientProvider).ping();
    });
    // When we are online again, replay the offline queue.
    ref.listen<bool>(isOnlineProvider, (prev, online) {
      if (online && prev != true) ref.read(syncQueueProvider.notifier).flush();
    });

    return MaterialApp.router(
      title: 'huddle',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, tenant),
      darkTheme: buildTheme(Brightness.dark, tenant),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Respect system text size up to 1.3× (UI.md §4).
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 1.3)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
