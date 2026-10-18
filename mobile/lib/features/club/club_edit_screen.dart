import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/image_upload.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Club Manager edits their club's profile: description, colours, venue, social handles, staff
/// and logo. The server checks the manager owns the club.
class ClubEditScreen extends ConsumerWidget {
  const ClubEditScreen({super.key, required this.clubId});

  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(clubProvider(clubId));
    return Scaffold(
      appBar: const TenantAppBar(title: 'Edit club'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'club_edit_screen',
              container: true,
              child: PageBody(
                children: [
                  AsyncView<Cached<ClubProfile>>(
                    id: 'club_edit',
                    value: value,
                    onRetry: () => ref.invalidate(clubProvider(clubId)),
                    builder: (r) => _ClubForm(club: r.data),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClubForm extends ConsumerStatefulWidget {
  const _ClubForm({required this.club});

  final ClubProfile club;

  @override
  ConsumerState<_ClubForm> createState() => _ClubFormState();
}

class _ClubFormState extends ConsumerState<_ClubForm> {
  late final _desc = TextEditingController(text: widget.club.description);
  late final _venue = TextEditingController(text: widget.club.venueName);
  late final _primary = TextEditingController(text: widget.club.primaryColor ?? '');
  late final _secondary = TextEditingController(text: widget.club.secondaryColor ?? '');
  late final _x = TextEditingController(text: widget.club.social['x'] ?? '');
  late final _ig = TextEditingController(text: widget.club.social['instagram'] ?? '');
  late List<StaffMember> _staff = [...widget.club.staff];
  bool _saving = false;
  String? _error;
  List<String> _bad = const [];

  static final _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

  @override
  void dispose() {
    for (final c in [_desc, _venue, _primary, _secondary, _x, _ig]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final bad = <String>[
      if (_venue.text.trim().isEmpty) 'venue',
      if (_primary.text.isNotEmpty && !_hex.hasMatch(_primary.text.trim())) 'primary',
      if (_secondary.text.isNotEmpty && !_hex.hasMatch(_secondary.text.trim())) 'secondary',
    ];
    if (bad.isNotEmpty) {
      setState(() => _bad = bad);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _bad = const [];
    });
    try {
      await ref.read(apiClientProvider).patch('/api/v1/clubs/${Uri.encodeComponent(widget.club.id)}', body: {
        'description': _desc.text.trim(),
        'venue': {'name': _venue.text.trim()},
        'colors': {if (_primary.text.isNotEmpty) 'primary': _primary.text.trim().toUpperCase(), if (_secondary.text.isNotEmpty) 'secondary': _secondary.text.trim().toUpperCase()},
        'social': {if (_x.text.trim().isNotEmpty) 'x': _x.text.trim(), if (_ig.text.trim().isNotEmpty) 'instagram': _ig.text.trim()},
        'staff': [for (final s in _staff) {'name': s.name, 'role': s.role}],
      });
      ref.invalidate(clubProvider(widget.club.id));
      ref.invalidate(clubsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Club profile saved.'), duration: AppMotion.snackbar));
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

  Future<void> _addStaff() async {
    final name = TextEditingController();
    var role = 'coach';
    final added = await showDialog<StaffMember>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add staff member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [for (final r in ['coach', 'assistant_coach', 'manager', 'physio', 'analyst', 'kit_manager']) DropdownMenuItem(value: r, child: Text(humanize(r)))],
                onChanged: (v) => setLocal(() => role = v ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => name.text.trim().isEmpty ? null : Navigator.pop(ctx, StaffMember(name: name.text.trim(), role: role)), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (added != null) setState(() => _staff = [..._staff, added]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.club;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ClubBadge(name: c.name, logoUrl: c.logoUrl, size: 56, decorative: false),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(c.name, style: text.titleLarge)),
          ],
        ),
        const SectionLabel('Logo'),
        ImageUploadPanel(
          id: 'club_logo_upload',
          path: '/api/v1/clubs/${Uri.encodeComponent(c.id)}/logo',
          buttonLabel: c.logoUrl == null ? 'Choose a logo' : 'Replace logo',
          onUploaded: (_) {
            ref.invalidate(clubProvider(c.id));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo uploaded.')));
          },
        ),
        const SectionLabel('Profile'),
        AppTextField(id: 'club_edit_description', label: 'Description', controller: _desc),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'club_edit_venue', label: 'Home venue', controller: _venue, errorText: _bad.contains('venue') ? 'Enter the venue name.' : null),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(child: AppTextField(id: 'club_edit_primary', label: 'Main colour', hint: '#1D4ED8', controller: _primary, errorText: _bad.contains('primary') || _bad.contains('colors') ? 'Use #RRGGBB.' : null)),
            const SizedBox(width: AppSpace.md),
            Expanded(child: AppTextField(id: 'club_edit_secondary', label: 'Second colour', hint: '#FFFFFF', controller: _secondary, errorText: _bad.contains('secondary') ? 'Use #RRGGBB.' : null)),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'club_edit_x', label: 'X handle', hint: '@club', controller: _x),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'club_edit_instagram', label: 'Instagram', hint: '@club', controller: _ig),
        const SectionLabel('Staff'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final s in _staff)
                ListTile(
                  leading: PersonAvatar(name: s.name),
                  title: Text(s.name),
                  subtitle: Text(humanize(s.role)),
                  trailing: IconButton(tooltip: 'Remove ${s.name}', icon: const Icon(Icons.close), onPressed: () => setState(() => _staff = _staff.where((x) => x != s).toList())),
                ),
              ListTile(leading: const Icon(Icons.person_add_alt), title: const Text('Add staff member'), onTap: _addStaff),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.lg),
          ErrorBanner(id: 'club_edit_error', message: _error!),
        ],
        const SizedBox(height: AppSpace.xl),
        AppButton(id: 'club_edit_save', label: 'Save changes', loading: _saving, onPressed: _save),
      ],
    );
  }
}
