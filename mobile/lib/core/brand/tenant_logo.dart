import 'package:flutter/material.dart';

import '../theme/tenant.dart';
import '../theme/typography.dart';
import '../widgets/remote_image.dart';

/// Tenant logo (UI.md §0.4): the uploaded logo when the Super-Admin set one, otherwise a circle
/// with the tenant initials in Sora 700 on the tenant brand. 32 dp in the app bar, 56 dp on login.
/// The initials are also the loading and offline fallback, so the logo never breaks.
class TenantLogo extends StatelessWidget {
  const TenantLogo({super.key, required this.tenant, this.size = 32, this.decorative = true});

  final TenantBrand tenant;
  final double size;

  /// True when the tenant name is printed next to the logo.
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Text(
        tenant.initials,
        maxLines: 1,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w700,
          fontSize: size * (tenant.initials.length > 2 ? 0.32 : 0.4),
          color: scheme.onPrimary,
          height: 1,
        ),
      ),
    );
    final logo = tenant.logoUrl == null
        ? initials
        : ClipOval(child: SizedBox.square(dimension: size, child: RemoteImage(path: tenant.logoUrl, fallback: initials)));
    if (decorative) return ExcludeSemantics(child: logo);
    return Semantics(label: '${tenant.name} logo', image: true, excludeSemantics: true, child: logo);
  }
}
