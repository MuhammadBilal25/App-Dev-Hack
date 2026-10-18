import 'package:flutter/material.dart';

import '../auth/user.dart';

/// White-label brand of a tenant (UI.md §3.3, FR-2.1). Only `brand` and the logo change between
/// tenants; every other token stays the same so contrast stays as checked.
@immutable
class TenantBrand {
  const TenantBrand({
    required this.id,
    required this.name,
    required this.initials,
    required this.brandLight,
    required this.brandDark,
    required this.softLight,
    required this.onSoftLight,
    required this.softDark,
    required this.onSoftDark,
    this.logoUrl,
  });

  final String id;
  final String name;
  final String initials;
  final Color brandLight;
  final Color brandDark;
  final Color softLight;
  final Color onSoftLight;
  final Color softDark;
  final Color onSoftDark;
  final String? logoUrl;

  Color brand(Brightness b) => b == Brightness.dark ? brandDark : brandLight;
  Color soft(Brightness b) => b == Brightness.dark ? softDark : softLight;
  Color onSoft(Brightness b) => b == Brightness.dark ? onSoftDark : onSoftLight;

  /// Text on brand: white in light mode, deep navy in dark mode (UI.md §3.1 onBrand).
  Color onBrand(Brightness b) => b == Brightness.dark ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF);

  static const alpha = TenantBrand(
    id: 'tenant-alpha',
    name: 'Alpha Sports',
    initials: 'AS',
    brandLight: Color(0xFF1D4ED8),
    brandDark: Color(0xFF8AB4FF),
    softLight: Color(0xFFE0E7FF),
    onSoftLight: Color(0xFF1E3A8A),
    softDark: Color(0xFF1E2A4A),
    onSoftDark: Color(0xFFC7D7FF),
  );

  static const beta = TenantBrand(
    id: 'tenant-beta',
    name: 'Beta Athletics',
    initials: 'BA',
    brandLight: Color(0xFF0F766E),
    brandDark: Color(0xFF5EEAD4),
    softLight: Color(0xFFCCFBF1),
    onSoftLight: Color(0xFF134E4A),
    softDark: Color(0xFF123B38),
    onSoftDark: Color(0xFF99F6E4),
  );

  /// Used before sign-in and for the Super Admin, who belongs to no tenant.
  static const platform = TenantBrand(
    id: 'huddle',
    name: 'huddle',
    initials: 'H',
    brandLight: Color(0xFF1D4ED8),
    brandDark: Color(0xFF8AB4FF),
    softLight: Color(0xFFE0E7FF),
    onSoftLight: Color(0xFF1E3A8A),
    softDark: Color(0xFF1E2A4A),
    onSoftDark: Color(0xFFC7D7FF),
  );

  static const _known = {'tenant-alpha': alpha, 'tenant-beta': beta};

  static TenantBrand byId(String? id) => _known[id] ?? platform;

  /// Brand for a tenant record from the API. Known tenants use the contrast-checked values above;
  /// an unknown tenant derives its brand from its own primary colour.
  static TenantBrand fromTenant(Tenant? t) {
    if (t == null) return platform;
    final known = _known[t.id];
    if (known != null && !t.custom) return known.withName(t.name, logoUrl: t.logoUrl);
    final seed = parseHex(t.primaryColor) ?? platform.brandLight;
    final light = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final dark = ColorScheme.fromSeed(seedColor: parseHex(t.darkColor) ?? seed, brightness: Brightness.dark);
    return TenantBrand(
      id: t.id,
      name: t.name,
      initials: initialsOf(t.name, max: 2),
      brandLight: light.primary,
      brandDark: dark.primary,
      softLight: light.primaryContainer,
      onSoftLight: light.onPrimaryContainer,
      softDark: dark.primaryContainer,
      onSoftDark: dark.onPrimaryContainer,
      logoUrl: t.logoUrl,
    );
  }

  TenantBrand withName(String name, {String? logoUrl}) => TenantBrand(
        id: id,
        name: name,
        initials: initials,
        brandLight: brandLight,
        brandDark: brandDark,
        softLight: softLight,
        onSoftLight: onSoftLight,
        softDark: softDark,
        onSoftDark: onSoftDark,
        logoUrl: logoUrl,
      );

  @override
  bool operator ==(Object other) =>
      other is TenantBrand && other.id == id && other.name == name && other.brandLight == brandLight && other.logoUrl == logoUrl;

  @override
  int get hashCode => Object.hash(id, name, brandLight, logoUrl);
}

/// First letters of up to [max] words: "Alpha FC" -> "AFC".
String initialsOf(String name, {int max = 3}) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = words.take(max).map((w) => w.characters.first.toUpperCase()).join();
  return letters.isEmpty ? '?' : letters;
}

Color? parseHex(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
