import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/user.dart';
import '../../core/brand/huddle_mark.dart';
import '../../core/brand/tenant_logo.dart';
import '../../core/layout/page_body.dart';
import '../../core/router/router.dart';
import '../../core/settings/server_address_sheet.dart';
import '../../core/settings/settings.dart';
import '../../core/sync/sync_queue.dart';
import '../../core/theme/tenant.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/role_badge.dart';
import '../shell/tab_page.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final tenant = ref.watch(tenantBrandProvider);
    final settings = ref.watch(settingsProvider);
    final queue = ref.watch(syncQueueProvider);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (user == null) return const SizedBox.shrink();

    final queueSummary = queue.items.isEmpty
        ? "Nothing waiting. You're all caught up."
        : [
            if (queue.pendingCount > 0) '${queue.pendingCount} waiting',
            if (queue.rejectedCount > 0) '${queue.rejectedCount} not applied',
          ].join(' · ');

    return TabPage(
      id: 'profile_screen',
      title: 'Profile',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              children: [
                if (tenant.id == TenantBrand.platform.id) const HuddleMark(size: 56) else TenantLogo(tenant: tenant, size: 56),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(user.email, style: text.bodyMedium!.copyWith(color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: AppSpace.sm),
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          RoleBadge(role: user.role),
                          Text(user.tenantId == null ? 'All organisations' : tenant.name, style: text.bodyMedium),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionLabel('My activity'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Semantics(
                identifier: 'profile_orders',
                button: true,
                child: ListTile(
                  minTileHeight: AppSize.rowMin,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('My orders and receipts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/orders'),
                ),
              ),
              if (user.role == UserRole.player && user.playerId != null)
                Semantics(
                  identifier: 'profile_my_player',
                  button: true,
                  child: ListTile(
                    minTileHeight: AppSize.rowMin,
                    leading: const Icon(Icons.sports_soccer),
                    title: const Text('My player profile'),
                    subtitle: const Text('Stats, club and roster history'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/player/${user.playerId}'),
                  ),
                ),
              if (user.clubId != null)
                ListTile(
                  minTileHeight: AppSize.rowMin,
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('My club'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(user.role == UserRole.clubManager ? '/manage/club' : '/club/${user.clubId}'),
                ),
              if (user.role == UserRole.leagueOrganizer || user.isSuperAdmin)
                Semantics(
                  identifier: 'profile_my_leagues',
                  button: true,
                  child: ListTile(
                    minTileHeight: AppSize.rowMin,
                    leading: const Icon(Icons.sports_score_outlined),
                    title: Text(user.isSuperAdmin ? 'Leagues: fixtures and scoring' : 'My leagues: fixtures and scoring'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/manage/organizer'),
                  ),
                ),
              if (user.isSuperAdmin)
                Semantics(
                  identifier: 'profile_admin',
                  button: true,
                  child: ListTile(
                    minTileHeight: AppSize.rowMin,
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Platform admin'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/admin'),
                  ),
                ),
            ],
          ),
        ),
        const SectionLabel('Sync'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            identifier: 'profile_sync_queue',
            button: true,
            child: ListTile(
              minTileHeight: AppSize.rowMin,
              leading: const Icon(Icons.sync),
              title: const Text('Sync queue'),
              subtitle: Text(queueSummary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.sync),
            ),
          ),
        ),
        const SectionLabel('Appearance'),
        Semantics(
          identifier: 'profile_appearance',
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setThemeMode(s.first),
            ),
          ),
        ),
        const SectionLabel('Server address'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            identifier: 'profile_server_address',
            button: true,
            child: ListTile(
              minTileHeight: AppSize.rowMin,
              leading: const Icon(Icons.dns_outlined),
              title: Text(settings.serverUrl, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text('Change', style: text.labelLarge!.copyWith(color: Theme.of(context).colorScheme.primary)),
              onTap: () => showServerAddressSheet(context),
            ),
          ),
        ),
        const SectionLabel('About'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              children: [
                const HuddleLockup(fontSize: 20),
                const SizedBox(width: AppSpace.md),
                Expanded(child: Text('Every club, one league home.', style: text.bodyMedium!.copyWith(color: muted))),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(
          id: 'profile_sign_out',
          label: 'Sign out',
          icon: Icons.logout,
          variant: AppButtonVariant.destructive,
          onPressed: () async {
            final pending = queue.pendingCount;
            final r = await ConfirmSheet.show(
              context,
              id: 'confirm_sign_out',
              title: 'Sign out?',
              message: pending > 0
                  ? 'You have $pending ${pending == 1 ? 'action' : 'actions'} waiting to sync. They stay on this phone and sync after you sign in again.'
                  : 'You will need your email and password to sign in again.',
              confirmLabel: 'Sign out',
              variant: AppButtonVariant.destructive,
            );
            if (r.confirmed) await ref.read(authControllerProvider.notifier).signOut();
          },
        ),
        const SizedBox(height: AppSpace.lg),
      ],
    );
  }
}
