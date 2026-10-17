/// Plain-language messages for backend error codes (UI.md §8). Show the sentence, never the code.
const Map<String, String> errorMessages = {
  'UNAUTHENTICATED': 'Your session has ended. Please sign in again.',
  'FORBIDDEN': "You don't have permission to do this with your role.",
  'VALIDATION_ERROR': 'Some details are missing or invalid. Check the highlighted fields.',
  'OUT_OF_STOCK': 'Sorry, this size just sold out. Try another size.',
  'PAYMENT_DECLINED': 'Your payment was declined. No money was taken. Try another card.',
  'PAYMENT_CAPTURE_FAILED': "We couldn't complete the payment. No money was taken. Please try again.",
  'INVALID_DISCOUNT_CODE': "That discount code isn't valid.",
  'MATCH_NOT_IN_PROGRESS': "This match isn't live, so scores can't be added.",
  'ILLEGAL_TRANSITION': "This match can't move to that status from where it is now.",
  'TIE_NOT_ALLOWED': "This sport doesn't allow a draw. Record a tie-break winner first.",
  'INVALID_COMPENSATION': "That event was already corrected or can't be corrected.",
  'INNINGS_COMPLETE': "This team's innings is already finished.",
  'SERIES_ALREADY_DECIDED': 'The series is already finished.',
  'TRANSFER_WINDOW_CLOSED': 'The transfer window is closed on that date.',
  'SQUAD_FULL': 'The destination squad is full.',
  'MIN_POSITION_VIOLATION': 'This move would leave the squad without enough players in that position.',
  'PLAYER_ON_LOAN': "This player is on loan and can't be moved until the loan ends.",
  'NOT_IN_SQUAD': "This player isn't in that squad anymore.",
  'CROSS_TENANT_TRANSFER': 'Players can only move between clubs in the same organisation.',
  'INVALID_BASE_VERSION': 'This change is out of date. Refresh and try again.',
  'RATE_LIMITED': 'Too many requests. Please wait a few seconds.',
};

const networkErrorMessage =
    "We couldn't reach the server. Your changes are saved and will sync when you're back online.";

/// Shown on the login screen instead of the "session ended" text, because there is no session yet.
const badCredentialsMessage = 'Email or password is incorrect. Check them and try again.';

const genericErrorMessage = 'Something went wrong. Please try again.';

const _notFoundMessage = "We couldn't find that. It may have been removed. Go back and try again.";
const _conflictMessage = 'This was already changed by someone else. Refresh and try again.';

/// The sentence to show for an error [code] and HTTP [status]. Unknown codes fall back by status:
/// any 5xx or network failure gets the offline-safe network message.
String messageFor(String? code, {int? status}) {
  final known = code == null ? null : errorMessages[code];
  if (known != null) return known;
  if (status == null || status >= 500) return networkErrorMessage;
  if (code != null && code.endsWith('_NOT_FOUND') || status == 404) return _notFoundMessage;
  if (code != null && code.startsWith('DUPLICATE_') || status == 409) return _conflictMessage;
  if (status == 401) return errorMessages['UNAUTHENTICATED']!;
  if (status == 403) return errorMessages['FORBIDDEN']!;
  if (status == 429) return errorMessages['RATE_LIMITED']!;
  if (status == 400) return errorMessages['VALIDATION_ERROR']!;
  return genericErrorMessage;
}
