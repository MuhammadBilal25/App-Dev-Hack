import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Text field with a visible label above it (UI.md §6.2), never placeholder-only. Errors appear
/// under the field in plain language.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.id,
    required this.label,
    required this.controller,
    this.errorText,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.suffix,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
  });

  final String id;
  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text(label, style: text.titleSmall)),
        const SizedBox(height: AppSpace.xs + 2),
        Semantics(
          identifier: id,
          label: label,
          textField: true,
          child: TextField(
            controller: controller,
            enabled: enabled,
            obscureText: obscure,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            autocorrect: false,
            enableSuggestions: !obscure,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            style: text.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
              suffixIcon: suffix,
              constraints: const BoxConstraints(minHeight: AppSize.inputHeight),
            ),
          ),
        ),
      ],
    );
  }
}
