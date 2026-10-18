/// The five roles of FR-5.1, as returned by the backend in `user.role`.
enum UserRole {
  superAdmin('super_admin', 'Super admin'),
  leagueOrganizer('league_organizer', 'League organizer'),
  clubManager('club_manager', 'Club manager'),
  player('player', 'Player'),
  viewer('viewer', 'Viewer');

  const UserRole(this.wire, this.label);

  final String wire;

  /// Sentence-case label for badges ("Club manager", not "CLUB_MANAGER").
  final String label;

  static UserRole fromWire(String? v) => values.firstWhere((r) => r.wire == v, orElse: () => viewer);
}

class Tenant {
  const Tenant({required this.id, required this.name, this.logoUrl, this.primaryColor, this.darkColor, this.custom = false});

  final String id;
  final String name;
  final String? logoUrl;
  final String? primaryColor;
  final String? darkColor;

  /// True when the Super-Admin changed the tenant's colours: they then replace the built-in brand.
  final bool custom;

  factory Tenant.fromJson(Map<String, dynamic> j) {
    final colors = j['colors'];
    return Tenant(
      id: j['tenant_id'] as String,
      name: (j['name'] as String?) ?? (j['tenant_id'] as String),
      logoUrl: j['logo_url'] as String?,
      primaryColor: colors is Map ? colors['primary'] as String? : null,
      darkColor: colors is Map ? colors['dark'] as String? : null,
      custom: j['brand_custom'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'tenant_id': id,
        'name': name,
        'logo_url': logoUrl,
        'colors': {'primary': primaryColor, 'dark': darkColor},
        'brand_custom': custom,
      };
}

/// The signed-in user, shaped like `GET /api/v1/me`.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.tenantId,
    this.tenant,
    this.leagueIds = const [],
    this.clubId,
    this.playerId,
    this.storeAccess = false,
  });

  final String id;
  final String email;
  final String name;
  final UserRole role;
  final String? tenantId;
  final Tenant? tenant;
  final List<String> leagueIds;
  final String? clubId;
  final String? playerId;

  /// Club Managers can manage their club's store only when the Super-Admin grants it.
  final bool storeAccess;

  bool get isSuperAdmin => role == UserRole.superAdmin;

  /// Score entry is shown only on the organizer's own leagues (UI.md §9).
  bool canScore(String? leagueId) =>
      isSuperAdmin || (role == UserRole.leagueOrganizer && leagueId != null && leagueIds.contains(leagueId));

  /// Roster tools are shown only on the manager's own club.
  bool canManageClub(String? clubId) =>
      isSuperAdmin || (role == UserRole.clubManager && clubId != null && this.clubId == clubId);

  factory AppUser.fromJson(Map<String, dynamic> j) {
    final t = j['tenant'];
    return AppUser(
      id: j['user_id'] as String,
      email: j['email'] as String,
      name: (j['name'] as String?) ?? (j['email'] as String),
      role: UserRole.fromWire(j['role'] as String?),
      tenantId: j['tenant_id'] as String?,
      tenant: t is Map<String, dynamic> ? Tenant.fromJson(t) : null,
      leagueIds: ((j['league_ids'] as List?) ?? const []).whereType<String>().toList(),
      clubId: j['club_id'] as String?,
      playerId: j['player_id'] as String?,
      storeAccess: j['store_access'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': id,
        'email': email,
        'name': name,
        'role': role.wire,
        'tenant_id': tenantId,
        'tenant': tenant?.toJson(),
        'league_ids': leagueIds,
        'club_id': clubId,
        'player_id': playerId,
        'store_access': storeAccess,
      };
}
