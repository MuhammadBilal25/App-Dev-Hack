import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../copy/error_messages.dart';
import '../settings/settings.dart';
import 'token_store.dart';
import 'user.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class SessionState {
  const SessionState._(this.status, this.user, this.notice);

  const SessionState.unknown() : this._(AuthStatus.unknown, null, null);
  const SessionState.signedOut({String? notice}) : this._(AuthStatus.signedOut, null, notice);
  const SessionState.signedIn(AppUser user) : this._(AuthStatus.signedIn, user, null);

  final AuthStatus status;
  final AppUser? user;

  /// Plain-language reason shown on the login screen, e.g. after the token expired.
  final String? notice;
}

class AuthController extends Notifier<SessionState> {
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  @override
  SessionState build() {
    Future.microtask(_restore);
    return const SessionState.unknown();
  }

  /// Opens straight from the cached profile so the app works in airplane mode, then refreshes
  /// the profile from `/api/v1/me` when the server answers.
  Future<void> _restore() async {
    final token = await _tokens.load();
    if (token == null) {
      state = const SessionState.signedOut();
      return;
    }
    final cached = await _tokens.loadUser();
    if (cached != null) state = SessionState.signedIn(cached);
    try {
      final me = AppUser.fromJson(await ref.read(apiClientProvider).get('/api/v1/me') as Map<String, dynamic>);
      await _tokens.saveUser(me);
      if (state.status == AuthStatus.signedIn || cached == null) state = SessionState.signedIn(me);
    } on ApiException catch (e) {
      if (e.isUnauthenticated) return; // handleUnauthorized already signed out.
      if (cached == null) state = const SessionState.signedOut();
    }
  }

  /// Throws [ApiException] with a plain-language message on failure.
  Future<void> signIn(String email, String password) async {
    final api = ref.read(apiClientProvider);
    final dynamic body;
    try {
      body = await api.post('/api/v1/auth/login', body: {'email': email.trim(), 'password': password}, auth: false);
    } on ApiException catch (e) {
      if (e.status == 401) {
        throw ApiException(code: e.code, status: e.status, message: badCredentialsMessage);
      }
      rethrow;
    }
    final map = body as Map<String, dynamic>;
    final user = AppUser.fromJson(map['user'] as Map<String, dynamic>);
    await _tokens.save(map['token'] as String, user);
    await ref.read(settingsProvider.notifier).setLastTenant(user.tenantId);
    state = SessionState.signedIn(user);
  }

  Future<void> signOut() async {
    await _tokens.clear();
    state = const SessionState.signedOut();
  }

  /// Called by the API client on any 401 for an authenticated request.
  Future<void> handleUnauthorized() async {
    if (state.status != AuthStatus.signedIn) return;
    await _tokens.clear();
    state = SessionState.signedOut(notice: errorMessages['UNAUTHENTICATED']);
  }
}

final authControllerProvider = NotifierProvider<AuthController, SessionState>(AuthController.new);

final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authControllerProvider).user);
