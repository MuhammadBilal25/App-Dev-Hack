import '../copy/error_messages.dart';

/// A failed API call. [message] is already plain language and safe to show; [code] is kept only
/// for logic (never displayed).
class ApiException implements Exception {
  const ApiException({required this.code, required this.status, required this.message, this.fields = const []});

  /// A request that never reached the server (offline, DNS, timeout, refused).
  const ApiException.network()
      : code = 'NETWORK',
        status = 0,
        message = networkErrorMessage,
        fields = const [];

  final String code;
  final int status;
  final String message;

  /// Fields named by a VALIDATION_ERROR, to highlight in forms.
  final List<String> fields;

  bool get isNetwork => status == 0 || status >= 500;
  bool get isUnauthenticated => status == 401;

  @override
  String toString() => 'ApiException($status $code)';
}
