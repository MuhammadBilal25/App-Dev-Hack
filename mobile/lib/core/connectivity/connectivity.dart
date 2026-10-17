import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the device has any network (Wi-Fi, mobile data, ethernet…).
final deviceOnlineProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool online(List<ConnectivityResult> r) => r.isNotEmpty && !r.every((x) => x == ConnectivityResult.none);
  try {
    yield online(await c.checkConnectivity());
  } on Exception {
    yield true;
  }
  yield* c.onConnectivityChanged.map(online);
});

/// Whether the last request reached the server. Updated by every API call, never by polling.
class ServerReachable extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) {
    if (state != value) state = value;
  }
}

final serverReachableProvider = NotifierProvider<ServerReachable, bool>(ServerReachable.new);

/// Online = the device has a network and the server answered the last request.
final isOnlineProvider = Provider<bool>((ref) {
  final device = ref.watch(deviceOnlineProvider).value ?? true;
  return device && ref.watch(serverReachableProvider);
});
