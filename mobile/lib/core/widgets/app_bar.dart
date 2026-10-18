import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../cart/cart.dart';
import '../brand/huddle_mark.dart';
import '../brand/tenant_logo.dart';
import '../theme/tenant.dart';
import '../theme/theme_providers.dart';
import '../theme/tokens.dart';
import 'role_badge.dart';

/// App bar used on every signed-in screen (UI.md §5, §9): tenant logo + name on tab roots, or a
/// labelled back arrow + title on deeper screens, and always the role badge.
class TenantAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const TenantAppBar({super.key, this.title});

  /// Null on tab roots (shows the tenant); set on deeper screens (shows back + title).
  final String? title;

  @override
  Size get preferredSize => const Size.fromHeight(AppSize.appBar);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantBrandProvider);
    final user = ref.watch(currentUserProvider);
    final deep = title != null;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: deep ? 0 : AppSpace.lg,
      leading: deep
          ? Semantics(
              identifier: 'app_bar_back',
              button: true,
              label: 'Back',
              excludeSemantics: true,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
              ),
            )
          : null,
      title: deep
          ? Semantics(header: true, child: Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis))
          : Semantics(
              identifier: 'app_bar_tenant',
              label: tenant.name,
              excludeSemantics: true,
              child: Row(
                children: [
                  if (tenant.id == TenantBrand.platform.id) const HuddleMark(size: 32) else TenantLogo(tenant: tenant, size: 32),
                  const SizedBox(width: AppSpace.md),
                  Flexible(child: Text(tenant.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
      actions: [
        if (user != null) const _CartButton(),
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.lg, left: AppSpace.sm),
            child: Center(child: RoleBadge(role: user.role)),
          ),
      ],
    );
  }
}

/// Cart with a count badge, on every signed-in screen.
class _CartButton extends ConsumerWidget {
  const _CartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartCountProvider);
    return Semantics(
      identifier: 'app_bar_cart',
      button: true,
      label: count == 0 ? 'Cart, empty' : 'Cart, $count ${count == 1 ? 'item' : 'items'}',
      excludeSemantics: true,
      child: IconButton(
        tooltip: 'Cart',
        onPressed: () => context.push('/cart'),
        icon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.shopping_cart_outlined)),
      ),
    );
  }
}
