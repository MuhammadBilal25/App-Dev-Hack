import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/brand/huddle_mark.dart';
import '../../core/brand/tenant_logo.dart';
import '../../core/settings/server_address_sheet.dart';
import '../../core/settings/settings.dart';
import '../../core/theme/tenant.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/sync_strip.dart';

/// Demo accounts from the backend README, one per role. All use the same password.
const _demoAccounts = [
  ('Super admin', 'admin@nascon.test'),
  ('League organizer', 'organizer@nascon.test'),
  ('Club manager', 'manager@nascon.test'),
  ('Player', 'player@nascon.test'),
  ('Viewer', 'viewer@nascon.test'),
];
const _demoPassword = 'Nascon@26';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _emailError;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    setState(() {
      _emailError = email.isEmpty
          ? 'Enter your email address.'
          : !email.contains('@')
              ? 'Enter a full email address, like name@club.com.'
              : null;
      _passwordError = _password.text.isEmpty ? 'Enter your password.' : null;
      _error = null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).signIn(email, _password.text);
      // The router redirects to Fixtures once the session is signed in.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _useDemo(String email) {
    setState(() {
      _email.text = email;
      _password.text = _demoPassword;
      _emailError = null;
      _passwordError = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final tenant = ref.watch(tenantBrandProvider);
    final server = ref.watch(settingsProvider.select((s) => s.serverUrl));
    final notice = ref.watch(authControllerProvider.select((s) => s.notice));
    final message = _error ?? notice;
    final knownTenant = tenant.id != TenantBrand.platform.id;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SyncStrip(showViewAction: false),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.lg),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: AppSpace.xl),
                            Center(
                              child: knownTenant ? TenantLogo(tenant: tenant, size: 56) : const HuddleMark(size: 56),
                            ),
                            const SizedBox(height: AppSpace.lg),
                            Semantics(
                              header: true,
                              child: Text('Sign in', textAlign: TextAlign.center, style: text.headlineSmall),
                            ),
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              knownTenant ? tenant.name : 'Every club, one league home.',
                              textAlign: TextAlign.center,
                              style: text.bodyLarge!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: AppSpace.xl),
                            if (message != null) ...[
                              ErrorBanner(id: 'login_error', message: message),
                              const SizedBox(height: AppSpace.lg),
                            ],
                            AppTextField(
                              id: 'login_email',
                              label: 'Email',
                              controller: _email,
                              errorText: _emailError,
                              hint: 'name@club.com',
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              enabled: !_loading,
                            ),
                            const SizedBox(height: AppSpace.lg),
                            AppTextField(
                              id: 'login_password',
                              label: 'Password',
                              controller: _password,
                              errorText: _passwordError,
                              obscure: _obscure,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _submit(),
                              enabled: !_loading,
                              suffix: Semantics(
                                identifier: 'login_password_toggle',
                                button: true,
                                label: _obscure ? 'Show password' : 'Hide password',
                                excludeSemantics: true,
                                child: IconButton(
                                  tooltip: _obscure ? 'Show password' : 'Hide password',
                                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.xl),
                            AppButton(id: 'login_submit', label: 'Sign in', loading: _loading, onPressed: _submit),
                            const SizedBox(height: AppSpace.md),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Server: $server', style: text.bodySmall),
                                Semantics(
                                  identifier: 'login_change_server',
                                  button: true,
                                  child: TextButton(
                                    onPressed: _loading ? null : () => showServerAddressSheet(context),
                                    child: const Text('Change server'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpace.lg),
                            _DemoAccounts(onPick: _loading ? null : _useDemo),
                            const SizedBox(height: AppSpace.xxl),
                            const _PoweredBy(),
                            const SizedBox(height: AppSpace.lg),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts({required this.onPick});

  final void Function(String email)? onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Semantics(
          identifier: 'login_demo_accounts',
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text('Demo accounts', style: text.titleMedium),
            subtitle: Text('Fill in one account per role', style: text.bodyMedium),
            childrenPadding: const EdgeInsets.only(bottom: AppSpace.sm),
            children: [
              for (final (role, email) in _demoAccounts)
                Semantics(
                  identifier: 'login_demo_${email.split('@').first}',
                  button: true,
                  child: ListTile(
                    minTileHeight: AppSize.rowMin,
                    title: Text(role),
                    subtitle: Text(email),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onPick == null ? null : () => onPick!(email),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "powered by" + 18 dp mark + "huddle" (UI.md §0.3).
class _PoweredBy extends StatelessWidget {
  const _PoweredBy();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: 'powered by huddle',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('powered by', style: Theme.of(context).textTheme.bodySmall!.copyWith(color: muted, letterSpacing: 0)),
          const SizedBox(width: AppSpace.sm),
          const HuddleMark(size: 18),
          const SizedBox(width: AppSpace.xs + 2),
          const HuddleWordmark(fontSize: 15),
        ],
      ),
    );
  }
}
