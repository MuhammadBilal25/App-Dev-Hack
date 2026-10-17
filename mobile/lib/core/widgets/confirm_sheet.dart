import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_button.dart';
import 'app_text_field.dart';

/// Result of a [ConfirmSheet]: whether the user confirmed, and the reason they typed (if asked).
typedef ConfirmResult = ({bool confirmed, String reason});

/// Confirmation sheet for risky actions (UI.md §6.7): says what will happen, optionally asks for a
/// reason, then Cancel (secondary) + the action button.
class ConfirmSheet extends StatefulWidget {
  const ConfirmSheet({
    super.key,
    required this.id,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.variant = AppButtonVariant.primary,
    this.reasonLabel,
  });

  final String id;
  final String title;
  final String message;
  final String confirmLabel;
  final AppButtonVariant variant;

  /// When set, a required reason field is shown with this label.
  final String? reasonLabel;

  static Future<ConfirmResult> show(
    BuildContext context, {
    required String id,
    required String title,
    required String message,
    required String confirmLabel,
    AppButtonVariant variant = AppButtonVariant.primary,
    String? reasonLabel,
  }) async {
    final r = await showModalBottomSheet<ConfirmResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConfirmSheet(
        id: id,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        variant: variant,
        reasonLabel: reasonLabel,
      ),
    );
    return r ?? (confirmed: false, reason: '');
  }

  @override
  State<ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<ConfirmSheet> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    if (widget.reasonLabel != null && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Add a short reason so others know why.');
      return;
    }
    Navigator.of(context).pop((confirmed: true, reason: _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: widget.id,
      container: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(header: true, child: Text(widget.title, style: text.titleLarge)),
                  const SizedBox(height: AppSpace.sm),
                  Text(widget.message, style: text.bodyLarge),
                  if (widget.reasonLabel != null) ...[
                    const SizedBox(height: AppSpace.lg),
                    AppTextField(
                      id: '${widget.id}_reason',
                      label: widget.reasonLabel!,
                      controller: _reason,
                      errorText: _error,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _confirm(),
                    ),
                  ],
                  const SizedBox(height: AppSpace.xl),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          id: '${widget.id}_cancel',
                          label: 'Cancel',
                          variant: AppButtonVariant.secondary,
                          onPressed: () => Navigator.of(context).pop((confirmed: false, reason: '')),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: AppButton(
                          id: '${widget.id}_confirm',
                          label: widget.confirmLabel,
                          variant: widget.variant,
                          onPressed: _confirm,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
