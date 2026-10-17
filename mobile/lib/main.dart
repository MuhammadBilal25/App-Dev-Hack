import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/cache/api_cache.dart';
import 'core/settings/settings.dart';
import 'core/sync/sync_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox<String>(syncBoxName);
  final cache = await Hive.openBox<String>(cacheBoxName);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        syncBoxProvider.overrideWithValue(box),
        cacheBoxProvider.overrideWithValue(cache),
      ],
      child: const HuddleApp(),
    ),
  );
}
