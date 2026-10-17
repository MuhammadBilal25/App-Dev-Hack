import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../settings/settings.dart';
import 'tenant.dart';

/// The tenant whose brand colours the whole app: the signed-in user's tenant, or before sign-in
/// the tenant of the last user on this device.
final tenantBrandProvider = Provider<TenantBrand>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user != null) return user.tenant != null ? TenantBrand.fromTenant(user.tenant) : TenantBrand.byId(user.tenantId);
  return TenantBrand.byId(ref.watch(settingsProvider.select((s) => s.lastTenantId)));
});
