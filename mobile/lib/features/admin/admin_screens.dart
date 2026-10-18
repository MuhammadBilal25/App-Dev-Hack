import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tenant.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/image_upload.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Shared scaffold for admin screens.
class _AdminPage extends StatelessWidget {
  const _AdminPage({required this.id, required this.title, required this.children, this.onRefresh, this.fab});

  final String id;
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final Widget? fab;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: TenantAppBar(title: title),
        floatingActionButton: fab,
        body: Column(children: [
          const SyncStrip(),
          Expanded(child: Semantics(identifier: id, container: true, child: PageBody(onRefresh: onRefresh, children: [...children, const SizedBox(height: 72)]))),
        ]),
      );
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> m, String key) => (m[key] as List? ?? const []).whereType<Map<String, dynamic>>().toList();

/// Runs an admin write and reports the result in plain language.
Future<bool> _adminCall(BuildContext context, Future<void> Function() task, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await task();
    messenger.showSnackBar(SnackBar(content: Text(done), duration: AppMotion.snackbar));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Super-Admin dashboard: platform counts and shortcuts to every configuration screen.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminGetProvider('dashboard'));
    final links = <(String, String, IconData, String)>[
      ('admin_sports', 'Sports and scoring rules', Icons.sports_outlined, '/admin/sports'),
      ('admin_leagues', 'Leagues, seasons and organizers', Icons.emoji_events_outlined, '/admin/leagues'),
      ('admin_clubs', 'Clubs and league membership', Icons.shield_outlined, '/admin/clubs'),
      ('admin_users', 'Users and roles', Icons.manage_accounts_outlined, '/admin/users'),
      ('admin_branding', 'Tenants and branding', Icons.palette_outlined, '/admin/tenants'),
      ('admin_store', 'Store categories and discount codes', Icons.sell_outlined, '/admin/store'),
      ('admin_settings', 'Platform settings', Icons.tune, '/admin/settings'),
      ('admin_activity', 'Activity and audit log', Icons.receipt_long_outlined, '/admin/activity'),
      ('admin_products', 'All products', Icons.inventory_2_outlined, '/manage/products'),
      ('admin_orders', 'All orders', Icons.local_shipping_outlined, '/manage/orders'),
    ];
    return _AdminPage(
      id: 'admin_dashboard',
      title: 'Platform admin',
      onRefresh: () => ref.refresh(adminGetProvider('dashboard').future),
      children: [
        AsyncView<Map<String, dynamic>>(
          id: 'admin_stats',
          value: value,
          onRetry: () => ref.invalidate(adminGetProvider('dashboard')),
          builder: (d) {
            final sports = (d['sports'] as Map?) ?? const {};
            final fx = (d['fixtures'] as Map?) ?? const {};
            final orders = (d['orders'] as Map?) ?? const {};
            final activity = _rows(d, 'recent_activity');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Tenants', value: '${d['tenants']}', icon: Icons.apartment_outlined),
                  StatTile(label: 'Active sports', value: '${sports['active']}/${sports['total']}', icon: Icons.sports_outlined),
                  StatTile(label: 'Leagues', value: '${d['leagues']}', icon: Icons.emoji_events_outlined),
                  StatTile(label: 'Clubs', value: '${d['clubs']}', icon: Icons.shield_outlined),
                  StatTile(label: 'Players', value: '${d['players']}', icon: Icons.groups_outlined),
                  StatTile(label: 'Live matches', value: '${fx['in_progress']}', icon: Icons.sensors),
                  StatTile(label: 'Orders', value: '${orders['count']}', icon: Icons.receipt_long_outlined),
                  StatTile(label: 'Revenue', value: formatPrice((orders['revenue_minor'] as num? ?? 0).toInt()), icon: Icons.payments_outlined),
                  StatTile(label: 'Low-stock variants', value: '${d['low_stock']}', icon: Icons.warning_amber_rounded),
                ]),
                const SectionLabel('Configure'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final (id, label, icon, route) in links)
                      Semantics(identifier: id, button: true, child: ListTile(minTileHeight: AppSize.rowMin, leading: Icon(icon), title: Text(label), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(route))),
                  ]),
                ),
                const SectionLabel('Recent activity'),
                if (activity.isEmpty) const EmptyState(id: 'admin_activity_empty', icon: Icons.history, message: 'No activity yet.') else _ActivityList(rows: activity),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final a in rows)
            ListTile(
              dense: true,
              leading: const Icon(Icons.bolt_outlined),
              title: Text('${humanize((a['action'] as String).replaceAll('.', ' · '))} → ${a['target']}'),
              subtitle: Text('${a['actor_email']} · ${DateFormat('d MMM, HH:mm').format(DateTime.tryParse('${a['at']}')?.toLocal() ?? DateTime.now())}'),
            ),
        ]),
      );
}

// ---------------------------------------------------------------------------------------------
// Sports
// ---------------------------------------------------------------------------------------------
class AdminSportsScreen extends ConsumerWidget {
  const AdminSportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminGetProvider('sports'));
    return _AdminPage(
      id: 'admin_sports_screen',
      title: 'Sports',
      onRefresh: () => ref.refresh(adminGetProvider('sports').future),
      fab: FloatingActionButton.extended(
        heroTag: 'new_sport',
        onPressed: () async {
          await context.push('/admin/sports/new');
          ref.invalidate(adminGetProvider('sports'));
        },
        icon: const Icon(Icons.add),
        label: const Text('New sport'),
      ),
      children: [
        Text('Each sport is configuration: its scoring model, events and roster rules. New sports work everywhere without app changes.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        AsyncView<Map<String, dynamic>>(
          id: 'admin_sports',
          value: value,
          onRetry: () => ref.invalidate(adminGetProvider('sports')),
          builder: (d) => Column(children: [
            for (final s in _rows(d, 'sports').map(Sport.fromJson))
              Card(
                child: SwitchListTile(
                  secondary: Icon(sportIcon(s.icon)),
                  title: Text(s.name),
                  subtitle: Text('${s.modelLabel} · ${s.leagueCount} leagues${s.demo ? ' · demo' : ''}'),
                  value: s.active,
                  onChanged: (v) async {
                    final ok = await _adminCall(context, () => ref.read(apiClientProvider).patch('/api/v1/admin/sports/${Uri.encodeComponent(s.id)}', body: {'active': v}), v ? '${s.name} is on.' : '${s.name} is off.');
                    if (ok) {
                      ref.invalidate(adminGetProvider('sports'));
                      ref.invalidate(sportsProvider);
                    }
                  },
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Create a sport from a form: identity, scoring model, scoring events and roster rules.
class AdminSportEditorScreen extends ConsumerStatefulWidget {
  const AdminSportEditorScreen({super.key});

  @override
  ConsumerState<AdminSportEditorScreen> createState() => _AdminSportEditorScreenState();
}

class _EventRow {
  final key = TextEditingController();
  final value = TextEditingController(text: '1');
  bool legal = true;
  bool wicket = false;
}

class _AdminSportEditorScreenState extends ConsumerState<AdminSportEditorScreen> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _p1 = TextEditingController(text: '2');
  final _p2 = TextEditingController(text: '45');
  final _p3 = TextEditingController(text: '6');
  final _p4 = TextEditingController(text: '10');
  final _min = TextEditingController(text: '5');
  final _max = TextEditingController(text: '20');
  final _position = TextEditingController();
  String _model = 'event';
  String _overtime = 'none';
  bool _draw = true;
  final List<_EventRow> _events = [_EventRow()..key.text = 'goal'];
  bool _saving = false;
  String? _error;
  List<String> _bad = const [];

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final periods = switch (_model) {
      'event' => {'count': _n(_p1), 'duration_minutes': _n(_p2)},
      'innings' => {'innings_per_team': _n(_p1), 'overs_per_innings': _n(_p2), 'balls_per_over': _n(_p3), 'wickets_per_innings': _n(_p4)},
      _ => {'best_of': _n(_p1)},
    };
    final events = {
      for (final e in _events)
        if (e.key.text.trim().isNotEmpty)
          e.key.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_'): switch (_model) {
            'event' => {'points': _n(e.value)},
            'innings' => {'runs': _n(e.value), 'legal_ball': e.legal, 'wicket': e.wicket},
            _ => {'rounds': _n(e.value)},
          },
    };
    try {
      await ref.read(apiClientProvider).post('/api/v1/admin/sports', body: {
        'sport_id': _id.text.trim().toLowerCase(),
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'scoring_model': _model,
        'periods': periods,
        'scoring_events': events,
        'draw_allowed': _draw,
        'overtime': {'policy': _overtime},
        'roster': {'min_squad_size': _n(_min), 'max_squad_size': _n(_max), 'required_positions': {if (_position.text.trim().isNotEmpty) _position.text.trim().toLowerCase(): 1}},
      });
      ref.invalidate(sportsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_name.text.trim()} created.')));
      context.pop();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _bad = e.fields;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final labels = switch (_model) {
      'event' => ['Periods', 'Minutes per period'],
      'innings' => ['Innings per side', 'Overs per innings', 'Balls per over', 'Wickets per innings'],
      _ => ['Best of (odd number)'],
    };
    final ctrls = [_p1, _p2, _p3, _p4];
    String? err(String f) => _bad.any((b) => b == f || b.startsWith('$f.')) ? 'Check this value.' : null;
    return _AdminPage(
      id: 'admin_sport_editor',
      title: 'New sport',
      children: [
        AppTextField(id: 'sport_id', label: 'Sport id (lowercase, e.g. netball)', controller: _id, errorText: err('sport_id')),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'sport_name', label: 'Name', controller: _name, errorText: err('name')),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'sport_description', label: 'Description', controller: _desc),
        const SectionLabel('Scoring model'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'event', label: Text('Points')),
            ButtonSegment(value: 'innings', label: Text('Innings')),
            ButtonSegment(value: 'round', label: Text('Best of')),
          ],
          selected: {_model},
          onSelectionChanged: (s) => setState(() {
            _model = s.first;
            _p1.text = _model == 'round' ? '3' : _model == 'innings' ? '1' : '2';
            _p2.text = _model == 'innings' ? '20' : '45';
          }),
        ),
        const SizedBox(height: AppSpace.md),
        for (var i = 0; i < labels.length; i++) ...[
          AppTextField(id: 'sport_p$i', label: labels[i], controller: ctrls[i], keyboardType: TextInputType.number, errorText: i == 0 ? err('periods') : null),
          const SizedBox(height: AppSpace.sm),
        ],
        const SectionLabel('Scoring events'),
        for (final e in _events)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(children: [
              Expanded(child: TextField(controller: e.key, decoration: const InputDecoration(labelText: 'Event name'))),
              const SizedBox(width: AppSpace.sm),
              SizedBox(width: 84, child: TextField(controller: e.value, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _model == 'innings' ? 'Runs' : _model == 'round' ? 'Counts' : 'Points'))),
              if (_model == 'innings') ...[
                Checkbox(value: e.legal, onChanged: (v) => setState(() => e.legal = v ?? true), semanticLabel: 'Legal ball'),
                Checkbox(value: e.wicket, onChanged: (v) => setState(() => e.wicket = v ?? false), semanticLabel: 'Wicket'),
              ],
            ]),
          ),
        if (_model == 'innings') Text('Tick 1: legal ball (counts towards the over). Tick 2: wicket.', style: text.bodySmall!.copyWith(letterSpacing: 0)),
        TextButton.icon(onPressed: () => setState(() => _events.add(_EventRow())), icon: const Icon(Icons.add), label: const Text('Add scoring event')),
        if (err('scoring_events') != null) const ErrorBanner(id: 'sport_events_error', message: 'Each event needs a lowercase name and a value.'),
        const SectionLabel('Rules'),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Draws allowed'), value: _draw, onChanged: (v) => setState(() => _draw = v)),
        DropdownButtonFormField<String>(
          initialValue: _overtime,
          decoration: const InputDecoration(labelText: 'When scores are level'),
          items: [for (final o in ['none', 'extra_time', 'shootout', 'golden_score', 'super_over']) DropdownMenuItem(value: o, child: Text(humanize(o)))],
          onChanged: (v) => setState(() => _overtime = v ?? 'none'),
        ),
        const SizedBox(height: AppSpace.md),
        Row(children: [
          Expanded(child: AppTextField(id: 'sport_min', label: 'Min squad', controller: _min, keyboardType: TextInputType.number, errorText: err('roster'))),
          const SizedBox(width: AppSpace.md),
          Expanded(child: AppTextField(id: 'sport_max', label: 'Max squad', controller: _max, keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'sport_position', label: 'Required position (optional, e.g. gk)', controller: _position),
        if (_error != null) ...[const SizedBox(height: AppSpace.lg), ErrorBanner(id: 'sport_editor_error', message: _error!)],
        const SizedBox(height: AppSpace.xl),
        AppButton(id: 'sport_save', label: 'Create sport', loading: _saving, onPressed: _save),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Leagues
// ---------------------------------------------------------------------------------------------
class AdminLeaguesScreen extends ConsumerWidget {
  const AdminLeaguesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminGetProvider('leagues'));
    return _AdminPage(
      id: 'admin_leagues_screen',
      title: 'Leagues',
      onRefresh: () => ref.refresh(adminGetProvider('leagues').future),
      fab: FloatingActionButton.extended(
        heroTag: 'new_league',
        onPressed: () async {
          await context.push('/admin/leagues/new');
          ref.invalidate(adminGetProvider('leagues'));
        },
        icon: const Icon(Icons.add),
        label: const Text('New league'),
      ),
      children: [
        AsyncView<Map<String, dynamic>>(
          id: 'admin_leagues',
          value: value,
          onRetry: () => ref.invalidate(adminGetProvider('leagues')),
          builder: (d) => Column(children: [
            for (final l in _rows(d, 'leagues').map(League.fromJson))
              Card(
                clipBehavior: Clip.antiAlias,
                child: LeagueTile(
                  league: l,
                  trailing: StatusChip(kind: l.status == 'active' ? StatusKind.success : StatusKind.neutral, label: humanize(l.status)),
                  onTap: () async {
                    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => _LeagueAdminSheet(league: l));
                    ref.invalidate(adminGetProvider('leagues'));
                  },
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Assign organizers, enter clubs, change status for one league.
class _LeagueAdminSheet extends ConsumerStatefulWidget {
  const _LeagueAdminSheet({required this.league});

  final League league;

  @override
  ConsumerState<_LeagueAdminSheet> createState() => _LeagueAdminSheetState();
}

class _LeagueAdminSheetState extends ConsumerState<_LeagueAdminSheet> {
  String? _organizer;
  String? _club;

  @override
  Widget build(BuildContext context) {
    final l = widget.league;
    final users = ref.watch(adminGetProvider('users?role=league_organizer&tenant_id=${l.tenantId}')).value;
    final clubs = ref.watch(clubsProvider).value?.data ?? const <ClubCard>[];
    final text = Theme.of(context).textTheme;
    final api = ref.read(apiClientProvider);
    final organizers = users == null ? const <Map<String, dynamic>>[] : _rows(users, 'users');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.name, style: text.titleLarge),
          Text('${l.sportName} · ${formatLabel(l.format)} · season ${l.season}', style: text.bodyMedium),
          if (l.organizers.isNotEmpty) Text('Organizers: ${l.organizers.join(', ')}', style: text.bodyMedium),
          const SectionLabel('Assign organizer'),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _organizer,
                isExpanded: true,
                hint: const Text('Choose a League Organizer'),
                items: [for (final u in organizers) DropdownMenuItem(value: u['user_id'] as String, child: Text('${u['name']} (${u['email']})', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _organizer = v),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            FilledButton(
              onPressed: _organizer == null ? null : () => _adminCall(context, () => api.post('/api/v1/admin/leagues/${Uri.encodeComponent(l.id)}/organizers', body: {'user_id': _organizer}), 'Organizer assigned.'),
              child: const Text('Assign'),
            ),
          ]),
          const SectionLabel('Enter a club'),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _club,
                isExpanded: true,
                hint: const Text('Choose a club of this tenant'),
                items: [for (final c in clubs) DropdownMenuItem(value: c.id, child: Text('${c.name} · ${c.sportName ?? ''}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _club = v),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            FilledButton(
              onPressed: _club == null ? null : () => _adminCall(context, () => api.post('/api/v1/admin/leagues/${Uri.encodeComponent(l.id)}/clubs', body: {'club_id': _club}), 'Club entered into ${l.name}.'),
              child: const Text('Add'),
            ),
          ]),
          const SectionLabel('Status'),
          Wrap(spacing: AppSpace.sm, children: [
            for (final s in ['active', 'completed', 'archived'])
              ChoiceChip(
                label: Text(humanize(s)),
                selected: l.status == s,
                onSelected: (_) async {
                  final nav = Navigator.of(context);
                  if (await _adminCall(context, () => api.patch('/api/v1/admin/leagues/${Uri.encodeComponent(l.id)}', body: {'status': s}), 'League marked $s.')) nav.pop();
                },
              ),
          ]),
          const SizedBox(height: AppSpace.lg),
          AppButton(id: 'league_admin_open', label: 'Open league page', variant: AppButtonVariant.secondary, onPressed: () => context.push('/leagues/${Uri.encodeComponent(l.id)}')),
        ],
      ),
    );
  }
}

class AdminLeagueEditorScreen extends ConsumerStatefulWidget {
  const AdminLeagueEditorScreen({super.key});

  @override
  ConsumerState<AdminLeagueEditorScreen> createState() => _AdminLeagueEditorScreenState();
}

class _AdminLeagueEditorScreenState extends ConsumerState<AdminLeagueEditorScreen> {
  final _name = TextEditingController();
  final _season = TextEditingController(text: '${DateTime.now().year}');
  final _desc = TextEditingController();
  final _spots = TextEditingController(text: '2');
  String? _tenant;
  String? _sport;
  String _format = 'round_robin';
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final l = await ref.read(apiClientProvider).post('/api/v1/admin/leagues', body: {
        'tenant_id': _tenant,
        'sport_id': _sport,
        'name': _name.text.trim(),
        'season': _season.text.trim(),
        'format': _format,
        'description': _desc.text.trim(),
        'qualification_spots': int.tryParse(_spots.text.trim()) ?? 2,
      }) as Map<String, dynamic>;
      ref.invalidate(leaguesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l['name']} created. Add clubs and assign an organizer next.')));
      context.pop();
    } on ApiException catch (e) {
      setState(() => _error = e.fields.isEmpty ? e.message : '${e.message} (${e.fields.join(', ')})');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenants = ref.watch(adminGetProvider('tenants')).value;
    final sports = ref.watch(adminGetProvider('sports')).value;
    return _AdminPage(
      id: 'admin_league_editor',
      title: 'New league',
      children: [
        DropdownButtonFormField<String>(
          initialValue: _tenant,
          decoration: const InputDecoration(labelText: 'Tenant'),
          items: [for (final t in tenants == null ? const <Map<String, dynamic>>[] : _rows(tenants, 'tenants')) DropdownMenuItem(value: t['tenant_id'] as String, child: Text(t['name'] as String))],
          onChanged: (v) => setState(() => _tenant = v),
        ),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<String>(
          initialValue: _sport,
          decoration: const InputDecoration(labelText: 'Sport'),
          items: [for (final s in sports == null ? const <Sport>[] : _rows(sports, 'sports').map(Sport.fromJson).where((s) => s.active)) DropdownMenuItem(value: s.id, child: Text(s.name))],
          onChanged: (v) => setState(() => _sport = v),
        ),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'league_name', label: 'League name', controller: _name),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'league_season', label: 'Season', controller: _season),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<String>(
          initialValue: _format,
          decoration: const InputDecoration(labelText: 'Competition format'),
          items: [for (final f in ['round_robin', 'swiss', 'single_elim', 'double_elim']) DropdownMenuItem(value: f, child: Text(formatLabel(f)))],
          onChanged: (v) => setState(() => _format = v ?? _format),
        ),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'league_spots', label: 'Qualification spots', controller: _spots, keyboardType: TextInputType.number),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'league_description', label: 'Description', controller: _desc),
        if (_error != null) ...[const SizedBox(height: AppSpace.lg), ErrorBanner(id: 'league_editor_error', message: _error!)],
        const SizedBox(height: AppSpace.xl),
        AppButton(id: 'league_save', label: 'Create league', loading: _saving, onPressed: _tenant == null || _sport == null ? null : _save),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Clubs
// ---------------------------------------------------------------------------------------------
class AdminClubsScreen extends ConsumerStatefulWidget {
  const AdminClubsScreen({super.key});

  @override
  ConsumerState<AdminClubsScreen> createState() => _AdminClubsScreenState();
}

class _AdminClubsScreenState extends ConsumerState<AdminClubsScreen> {
  final _name = TextEditingController();
  final _venue = TextEditingController();
  final _color = TextEditingController(text: '#1D4ED8');
  String? _league;
  bool _saving = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).post('/api/v1/admin/clubs', body: {
        'name': _name.text.trim(),
        'league_id': _league,
        'venue': {'name': _venue.text.trim()},
        if (_color.text.trim().isNotEmpty) 'colors': {'primary': _color.text.trim().toUpperCase()},
      });
      ref.invalidate(clubsProvider);
      _name.clear();
      _venue.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Club created and entered into the league.')));
    } on ApiException catch (e) {
      setState(() => _error = e.fields.isEmpty ? e.message : '${e.message} (${e.fields.join(', ')})');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagues = ref.watch(adminGetProvider('leagues')).value;
    final clubs = ref.watch(clubsProvider);
    return _AdminPage(
      id: 'admin_clubs_screen',
      title: 'Clubs',
      onRefresh: () => ref.refresh(clubsProvider.future),
      children: [
        const SectionLabel('Create a club'),
        DropdownButtonFormField<String>(
          initialValue: _league,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Home league'),
          items: [for (final l in leagues == null ? const <League>[] : _rows(leagues, 'leagues').map(League.fromJson)) DropdownMenuItem(value: l.id, child: Text('${l.name} (${l.sportName})', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _league = v),
        ),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'club_new_name', label: 'Club name', controller: _name),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'club_new_venue', label: 'Home venue', controller: _venue),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'club_new_color', label: 'Main colour (#RRGGBB)', controller: _color),
        if (_error != null) ...[const SizedBox(height: AppSpace.md), ErrorBanner(id: 'club_new_error', message: _error!)],
        const SizedBox(height: AppSpace.md),
        AppButton(id: 'club_new_save', label: 'Create club', loading: _saving, onPressed: _league == null ? null : _create),
        const SectionLabel('All clubs'),
        AsyncView<Cached<List<ClubCard>>>(
          id: 'admin_clubs',
          value: clubs,
          onRetry: () => ref.invalidate(clubsProvider),
          builder: (r) => Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final c in r.data)
                ListTile(
                  leading: ClubBadge(name: c.name, logoUrl: c.logoUrl, size: 28),
                  title: Text(c.name),
                  subtitle: Text([c.sportName, c.leagueName].whereType<String>().join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/club/${Uri.encodeComponent(c.id)}'),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------------------------
const _roleLabels = {'super_admin': 'Super admin', 'league_organizer': 'League organizer', 'club_manager': 'Club manager', 'player': 'Player', 'viewer': 'Viewer'};

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  String? _role;

  @override
  Widget build(BuildContext context) {
    final path = _role == null ? 'users' : 'users?role=$_role';
    final value = ref.watch(adminGetProvider(path));
    return _AdminPage(
      id: 'admin_users_screen',
      title: 'Users and roles',
      onRefresh: () => ref.refresh(adminGetProvider(path).future),
      fab: FloatingActionButton.extended(
        heroTag: 'new_user',
        onPressed: () async {
          await context.push('/admin/users/new');
          ref.invalidate(adminGetProvider(path));
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New user'),
      ),
      children: [
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          ChoiceChip(label: const Text('All'), selected: _role == null, onSelected: (_) => setState(() => _role = null)),
          for (final e in _roleLabels.entries) ChoiceChip(label: Text(e.value), selected: _role == e.key, onSelected: (_) => setState(() => _role = e.key)),
        ]),
        const SizedBox(height: AppSpace.md),
        AsyncView<Map<String, dynamic>>(
          id: 'admin_users',
          value: value,
          onRetry: () => ref.invalidate(adminGetProvider(path)),
          builder: (d) => Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final u in _rows(d, 'users'))
                ListTile(
                  leading: PersonAvatar(name: u['name'] as String),
                  title: Text(u['name'] as String),
                  subtitle: Text('${u['email']} · ${_roleLabels[u['role']]}${u['tenant_id'] == null ? '' : ' · ${u['tenant_id']}'}'),
                  trailing: u['active'] == false ? const StatusChip(kind: StatusKind.neutral, label: 'Disabled') : const Icon(Icons.chevron_right),
                  onTap: () async {
                    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => _UserSheet(user: u));
                    ref.invalidate(adminGetProvider(path));
                  },
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Change role, assignments, store access or disable an account.
class _UserSheet extends ConsumerStatefulWidget {
  const _UserSheet({required this.user});

  final Map<String, dynamic> user;

  @override
  ConsumerState<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends ConsumerState<_UserSheet> {
  late String _role = widget.user['role'] as String;
  late bool _active = widget.user['active'] != false;
  late bool _store = widget.user['store_access'] == true;
  late final List<String> _leagues = [...((widget.user['league_ids'] as List?) ?? const []).cast<String>()];
  late String? _club = widget.user['club_id'] as String?;

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final text = Theme.of(context).textTheme;
    final leagues = ref.watch(adminGetProvider('leagues')).value;
    final clubs = ref.watch(clubsProvider).value?.data ?? const <ClubCard>[];
    final tenantLeagues = leagues == null ? const <League>[] : _rows(leagues, 'leagues').map(League.fromJson).where((l) => l.tenantId == u['tenant_id']).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(u['name'] as String, style: text.titleLarge),
          Text(u['email'] as String, style: text.bodyMedium),
          const SectionLabel('Role'),
          DropdownButtonFormField<String>(
            initialValue: _role,
            items: [for (final e in _roleLabels.entries.where((e) => e.key != 'super_admin' || _role == 'super_admin')) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          if (_role == 'league_organizer') ...[
            const SectionLabel('Leagues they run'),
            for (final l in tenantLeagues)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.name),
                value: _leagues.contains(l.id),
                onChanged: (v) => setState(() => v == true ? _leagues.add(l.id) : _leagues.remove(l.id)),
              ),
          ],
          if (_role == 'club_manager') ...[
            const SectionLabel('Club'),
            DropdownButtonFormField<String>(
              initialValue: clubs.any((c) => c.id == _club) ? _club : null,
              isExpanded: true,
              items: [for (final c in clubs) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _club = v),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Can manage the club store'), value: _store, onChanged: (v) => setState(() => _store = v)),
          ],
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Account active'), subtitle: const Text('Disabled accounts are signed out at once.'), value: _active, onChanged: (v) => setState(() => _active = v)),
          const SizedBox(height: AppSpace.lg),
          AppButton(
            id: 'user_save',
            label: 'Save changes',
            onPressed: () async {
              final nav = Navigator.of(context);
              final ok = await _adminCall(
                context,
                () => ref.read(apiClientProvider).patch('/api/v1/admin/users/${Uri.encodeComponent(u['user_id'] as String)}', body: {
                  'role': _role,
                  'active': _active,
                  if (_role == 'league_organizer') 'league_ids': _leagues,
                  if (_role == 'club_manager') 'club_id': _club,
                  if (_role == 'club_manager') 'store_access': _store,
                }),
                'User updated.',
              );
              if (ok) nav.pop();
            },
          ),
        ],
      ),
    );
  }
}

class AdminUserEditorScreen extends ConsumerStatefulWidget {
  const AdminUserEditorScreen({super.key});

  @override
  ConsumerState<AdminUserEditorScreen> createState() => _AdminUserEditorScreenState();
}

class _AdminUserEditorScreenState extends ConsumerState<AdminUserEditorScreen> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  String _role = 'viewer';
  String? _tenant;
  String? _club;
  bool _saving = false;
  String? _error;
  List<String> _bad = const [];

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).post('/api/v1/admin/users', body: {
        'email': _email.text.trim(),
        'name': _name.text.trim(),
        'password': _password.text,
        'role': _role,
        'tenant_id': ?_tenant,
        if (_role == 'club_manager') 'club_id': _club,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created.')));
      context.pop();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _bad = e.fields;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenants = ref.watch(adminGetProvider('tenants')).value;
    final clubs = (ref.watch(clubsProvider).value?.data ?? const <ClubCard>[]);
    return _AdminPage(
      id: 'admin_user_editor',
      title: 'New user',
      children: [
        AppTextField(id: 'user_email', label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress, errorText: _bad.contains('email') ? 'Enter a valid email.' : null),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'user_name', label: 'Full name', controller: _name, errorText: _bad.contains('name') ? 'Enter a name.' : null),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'user_password', label: 'Temporary password (8+ characters)', controller: _password, obscure: true, errorText: _bad.contains('password') ? 'At least 8 characters.' : null),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Role'),
          items: [for (final e in _roleLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _role = v ?? _role),
        ),
        if (_role != 'super_admin') ...[
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<String>(
            initialValue: _tenant,
            decoration: InputDecoration(labelText: 'Tenant', errorText: _bad.contains('tenant_id') ? 'Choose a tenant.' : null),
            items: [for (final t in tenants == null ? const <Map<String, dynamic>>[] : _rows(tenants, 'tenants')) DropdownMenuItem(value: t['tenant_id'] as String, child: Text(t['name'] as String))],
            onChanged: (v) => setState(() => _tenant = v),
          ),
        ],
        if (_role == 'club_manager') ...[
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<String>(
            initialValue: _club,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Club', errorText: _bad.contains('club_id') ? 'Choose a club of this tenant.' : null),
            items: [for (final c in clubs) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _club = v),
          ),
        ],
        if (_role == 'league_organizer') const Padding(padding: EdgeInsets.only(top: AppSpace.sm), child: Text('Assign leagues after creating the account (Leagues → choose a league).')),
        if (_error != null) ...[const SizedBox(height: AppSpace.lg), ErrorBanner(id: 'user_editor_error', message: _error!)],
        const SizedBox(height: AppSpace.xl),
        AppButton(id: 'user_create', label: 'Create account', loading: _saving, onPressed: _save),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Tenants and branding
// ---------------------------------------------------------------------------------------------
class AdminTenantsScreen extends ConsumerWidget {
  const AdminTenantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminGetProvider('tenants'));
    return _AdminPage(
      id: 'admin_tenants_screen',
      title: 'Tenants and branding',
      onRefresh: () => ref.refresh(adminGetProvider('tenants').future),
      children: [
        Text('Each tenant is a white-label organisation with its own name, logo and colour. Members see it after their next sign-in.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        AsyncView<Map<String, dynamic>>(
          id: 'admin_tenants',
          value: value,
          onRetry: () => ref.invalidate(adminGetProvider('tenants')),
          builder: (d) => Column(children: [for (final t in _rows(d, 'tenants')) _TenantCard(json: t)]),
        ),
      ],
    );
  }
}

class _TenantCard extends ConsumerStatefulWidget {
  const _TenantCard({required this.json});

  final Map<String, dynamic> json;

  @override
  ConsumerState<_TenantCard> createState() => _TenantCardState();
}

class _TenantCardState extends ConsumerState<_TenantCard> {
  late final _name = TextEditingController(text: widget.json['name'] as String);
  late final _color = TextEditingController(text: ((widget.json['colors'] as Map?)?['primary'] as String?) ?? '');

  @override
  Widget build(BuildContext context) {
    final t = widget.json;
    final id = t['tenant_id'] as String;
    final text = Theme.of(context).textTheme;
    final swatch = parseHex(_color.text.trim());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(width: 28, height: 28, decoration: BoxDecoration(color: swatch ?? Colors.grey, shape: BoxShape.circle)),
              const SizedBox(width: AppSpace.md),
              Expanded(child: Text('${t['name']}', style: text.titleMedium)),
              Text('${t['club_count']} clubs · ${t['user_count']} users', style: text.bodySmall!.copyWith(letterSpacing: 0)),
            ]),
            const SizedBox(height: AppSpace.md),
            AppTextField(id: 'tenant_name_$id', label: 'Name', controller: _name),
            const SizedBox(height: AppSpace.sm),
            AppTextField(id: 'tenant_color_$id', label: 'Brand colour (#RRGGBB)', controller: _color, onChanged: (_) => setState(() {})),
            const SizedBox(height: AppSpace.sm),
            AppButton(
              id: 'tenant_save_$id',
              label: 'Save branding',
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                if (await _adminCall(context, () => ref.read(apiClientProvider).patch('/api/v1/admin/tenants/${Uri.encodeComponent(id)}', body: {'name': _name.text.trim(), 'colors': {'primary': _color.text.trim().toUpperCase()}}), 'Branding saved.')) {
                  ref.invalidate(adminGetProvider('tenants'));
                }
              },
            ),
            const SectionLabel('Logo'),
            ImageUploadPanel(
              id: 'tenant_logo_$id',
              path: '/api/v1/admin/tenants/${Uri.encodeComponent(id)}/logo',
              buttonLabel: t['logo_url'] == null ? 'Choose a logo' : 'Replace logo',
              onUploaded: (_) {
                ref.invalidate(adminGetProvider('tenants'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo uploaded.')));
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Store configuration, settings, activity
// ---------------------------------------------------------------------------------------------
class AdminStoreScreen extends ConsumerStatefulWidget {
  const AdminStoreScreen({super.key});

  @override
  ConsumerState<AdminStoreScreen> createState() => _AdminStoreScreenState();
}

class _AdminStoreScreenState extends ConsumerState<AdminStoreScreen> {
  final _category = TextEditingController();
  final _code = TextEditingController();
  final _percent = TextEditingController(text: '10');

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final discounts = ref.watch(adminGetProvider('discounts'));
    final api = ref.read(apiClientProvider);
    return _AdminPage(
      id: 'admin_store_screen',
      title: 'Store configuration',
      children: [
        const SectionLabel('Categories'),
        AsyncView<List<Facet>>(
          id: 'admin_categories',
          value: categories,
          onRetry: () => ref.invalidate(categoriesProvider),
          builder: (list) => Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            for (final c in list)
              InputChip(
                label: Text(c.name),
                onDeleted: () async {
                  if (await _adminCall(context, () => api.delete('/api/v1/admin/categories/${Uri.encodeComponent(c.id)}'), '${c.name} removed.')) ref.invalidate(categoriesProvider);
                },
                deleteButtonTooltipMessage: 'Remove ${c.name}',
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          Expanded(child: AppTextField(id: 'category_new', label: 'New category', controller: _category)),
          const SizedBox(width: AppSpace.sm),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: FilledButton(
              onPressed: () async {
                if (await _adminCall(context, () => api.post('/api/v1/admin/categories', body: {'name': _category.text.trim()}), 'Category added.')) {
                  _category.clear();
                  ref.invalidate(categoriesProvider);
                }
              },
              child: const Text('Add'),
            ),
          ),
        ]),
        const SectionLabel('Discount codes'),
        AsyncView<Map<String, dynamic>>(
          id: 'admin_discounts',
          value: discounts,
          onRetry: () => ref.invalidate(adminGetProvider('discounts')),
          builder: (d) => Card(
            child: Column(children: [
              for (final c in _rows(d, 'discounts'))
                SwitchListTile(
                  title: Text('${c['code']}'),
                  subtitle: Text('${c['percent']}% off'),
                  value: c['active'] != false,
                  onChanged: (v) async {
                    if (await _adminCall(context, () => api.post('/api/v1/admin/discounts', body: {'code': c['code'], 'active': v}), 'Code ${v ? 'enabled' : 'disabled'}.')) ref.invalidate(adminGetProvider('discounts'));
                  },
                ),
            ]),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          Expanded(child: AppTextField(id: 'discount_code', label: 'Code (A-Z, 0-9)', controller: _code)),
          const SizedBox(width: AppSpace.sm),
          SizedBox(width: 90, child: AppTextField(id: 'discount_percent', label: '% off', controller: _percent, keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppButton(
          id: 'discount_save',
          label: 'Save discount code',
          variant: AppButtonVariant.secondary,
          onPressed: () async {
            if (await _adminCall(context, () => api.post('/api/v1/admin/discounts', body: {'code': _code.text.trim().toUpperCase(), 'percent': int.tryParse(_percent.text.trim()) ?? 0}), 'Discount code saved.')) {
              _code.clear();
              ref.invalidate(adminGetProvider('discounts'));
            }
          },
        ),
      ],
    );
  }
}

class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminGetProvider('settings'));
    final api = ref.read(apiClientProvider);
    Future<void> set(String k, Object v) async {
      if (await _adminCall(context, () => api.patch('/api/v1/admin/settings', body: {k: v}), 'Setting saved.')) ref.invalidate(adminGetProvider('settings'));
    }

    return _AdminPage(
      id: 'admin_settings_screen',
      title: 'Platform settings',
      children: [
        AsyncView<Map<String, dynamic>>(
          id: 'admin_settings',
          value: value,
          onRetry: () => ref.invalidate(adminGetProvider('settings')),
          builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              child: SwitchListTile(
                title: const Text('League Organizers may create clubs'),
                subtitle: const Text('In the leagues they run. Otherwise only the Super-Admin creates clubs.'),
                value: s['organizer_can_create_clubs'] == true,
                onChanged: (v) => set('organizer_can_create_clubs', v),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Low-stock threshold'),
                subtitle: Text('Variants with ${s['low_stock_threshold']} or fewer units are flagged.'),
                trailing: DropdownButton<int>(
                  value: (s['low_stock_threshold'] as num).toInt(),
                  items: [for (final n in {0, 1, 2, 3, 5, 10, (s['low_stock_threshold'] as num).toInt()}) DropdownMenuItem(value: n, child: Text('$n'))],
                  onChanged: (v) => v == null ? null : set('low_stock_threshold', v),
                ),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Minimum rest between fixtures'),
                subtitle: Text('${s['min_rest_hours']} hours (used by conflict detection).'),
                trailing: DropdownButton<int>(
                  value: (s['min_rest_hours'] as num).toInt(),
                  items: [for (final n in {0, 6, 12, 24, 48, (s['min_rest_hours'] as num).toInt()}) DropdownMenuItem(value: n, child: Text('$n h'))],
                  onChanged: (v) => v == null ? null : set('min_rest_hours', v),
                ),
              ),
            ),
            Card(child: ListTile(title: const Text('Currency'), trailing: Text('${s['currency']}'))),
          ]),
        ),
      ],
    );
  }
}

class AdminActivityScreen extends ConsumerWidget {
  const AdminActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminGetProvider('activity?limit=200'));
    return _AdminPage(
      id: 'admin_activity_screen',
      title: 'Activity log',
      onRefresh: () => ref.refresh(adminGetProvider('activity?limit=200').future),
      children: [
        Text('Every change made through the app or API: who, what, when. Entries are append-only.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        AsyncView<Map<String, dynamic>>(
          id: 'admin_activity',
          value: value,
          onRetry: () => ref.invalidate(adminGetProvider('activity?limit=200')),
          builder: (d) {
            final rows = _rows(d, 'activity');
            if (rows.isEmpty) return const EmptyState(id: 'activity_empty', icon: Icons.history, message: 'No activity yet.');
            return _ActivityList(rows: rows);
          },
        ),
      ],
    );
  }
}
