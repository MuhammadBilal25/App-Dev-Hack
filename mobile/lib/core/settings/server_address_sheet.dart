import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import 'settings.dart';

/// Bottom sheet to change the server address (reachable from Login and Profile).
Future<void> showServerAddressSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ServerAddressSheet(),
  );
}

class _ServerAddressSheet extends ConsumerStatefulWidget {
  const _ServerAddressSheet();

  @override
  ConsumerState<_ServerAddressSheet> createState() => _ServerAddressSheetState();
}

class _ServerAddressSheetState extends ConsumerState<_ServerAddressSheet> {
  late final _url = TextEditingController(text: ref.read(settingsProvider).serverUrl);
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await ref.read(settingsProvider.notifier).setServerUrl(_url.text);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Enter an address like http://192.168.1.20:8080');
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Server set to ${ref.read(settingsProvider).serverUrl}'), duration: AppMotion.snackbar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'server_sheet',
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
                  Semantics(header: true, child: Text('Server address', style: text.titleLarge)),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'The address of the league server. On a phone, use the computer\'s Wi-Fi address, not localhost.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AppTextField(
                    id: 'server_url_field',
                    label: 'Server address',
                    controller: _url,
                    errorText: _error,
                    hint: defaultServerUrl,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          id: 'server_cancel',
                          label: 'Cancel',
                          variant: AppButtonVariant.secondary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(child: AppButton(id: 'server_save', label: 'Save', onPressed: _save)),
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
