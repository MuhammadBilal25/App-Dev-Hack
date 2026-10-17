import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/sync/submit.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'add_player_sheet.dart';

enum RosterAction { transfer, loan, release }

Future<void> showRosterManageSheet(BuildContext context, ClubProfile club) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RosterManageSheet(club: club),
  );
}

/// Transfer / loan / release for the club manager. The change is queued as a `roster_transfer`
/// offline action (base_version = the player's audit entry count) and synced at once if online.
class RosterManageSheet extends ConsumerStatefulWidget {
  const RosterManageSheet({super.key, required this.club});

  final ClubProfile club;

  @override
  ConsumerState<RosterManageSheet> createState() => _RosterManageSheetState();
}

class _RosterManageSheetState extends ConsumerState<RosterManageSheet> {
  static final _wire = DateFormat('yyyy-MM-dd');
  static final _show = DateFormat('EEE d MMM y');

  final _reason = TextEditingController();
  RosterPlayer? _player;
  RosterAction _action = RosterAction.transfer;
  String? _toClub;
  DateTime _effective = DateTime.now();
  DateTime _loanEnd = DateTime.now().add(const Duration(days: 30));
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool loanEnd) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: loanEnd ? _loanEnd : _effective,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => loanEnd ? _loanEnd = picked : _effective = picked);
  }

  Future<void> _submit() async {
    final p = _player;
    final needsTo = _action != RosterAction.release;
    if (p == null || (needsTo && _toClub == null)) {
      setState(() => _error = p == null ? 'Choose a player first.' : 'Choose the club the player moves to.');
      return;
    }
    if (_action == RosterAction.loan && !_loanEnd.isAfter(_effective)) {
      setState(() => _error = 'The loan must end after it starts.');
      return;
    }
    final clubs = ref.read(clubsProvider).value?.data ?? const <ClubRef>[];
    final toName = clubs.where((c) => c.id == _toClub).map((c) => c.name).firstOrNull ?? _toClub ?? '';
    final verb = switch (_action) {
      RosterAction.transfer => 'Transfer ${p.name} to $toName',
      RosterAction.loan => 'Loan ${p.name} to $toName until ${_show.format(_loanEnd)}',
      RosterAction.release => 'Release ${p.name}',
    };
    final confirm = await ConfirmSheet.show(
      context,
      id: 'confirm_roster',
      title: '$verb?',
      message: 'From ${widget.club.name}, effective ${_show.format(_effective)}. '
          '${_action == RosterAction.release ? 'The player leaves the squad.' : 'This is recorded in the audit trail.'}',
      confirmLabel: switch (_action) {
        RosterAction.transfer => 'Transfer',
        RosterAction.loan => 'Loan',
        RosterAction.release => 'Release',
      },
      variant: _action == RosterAction.release ? AppButtonVariant.destructive : AppButtonVariant.primary,
    );
    if (!confirm.confirmed || !mounted) return;
    setState(() => _busy = true);
    final user = ref.read(currentUserProvider);
    final reason = _reason.text.trim();
    await submitAction(
      context,
      ref,
      type: 'roster_transfer',
      baseVersion: p.version,
      label: verb,
      payload: {
        'request_id': newClientId('req'),
        'league_id': widget.club.leagueId,
        'player_id': p.id,
        'type': _action.name,
        'from_squad_id': widget.club.id,
        if (needsTo) 'to_squad_id': _toClub,
        'effective_date': _wire.format(_effective),
        if (_action == RosterAction.loan) 'loan_end_date': _wire.format(_loanEnd),
        if (reason.isNotEmpty) 'reason': reason,
        if (user != null) 'requested_by': user.email,
      },
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final others = (ref.watch(clubsProvider).value?.data ?? const <ClubRef>[]).where((c) => c.id != widget.club.id).toList();

    Widget field(String label, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.titleSmall),
            const SizedBox(height: AppSpace.xs + 2),
            child,
            const SizedBox(height: AppSpace.lg),
          ],
        );

    Widget dropdown<T>(String id, String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) => Semantics(
          identifier: id,
          label: label,
          child: InputDecorator(
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 2)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                hint: Text('Choose…', style: text.bodyLarge!.copyWith(color: scheme.onSurfaceVariant)),
                items: items,
                onChanged: _busy ? null : onChanged,
              ),
            ),
          ),
        );

    Widget dateButton(String id, DateTime d, bool loanEnd) => Semantics(
          identifier: id,
          button: true,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickDate(loanEnd),
            icon: const Icon(Icons.event),
            label: Text(_show.format(d)),
          ),
        );

    return Semantics(
      identifier: 'roster_manage_sheet',
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(header: true, child: Text('Manage ${widget.club.name}', style: text.titleLarge)),
                  const SizedBox(height: AppSpace.md),
                  AppButton(
                    id: 'roster_add_player',
                    label: 'Add player',
                    icon: Icons.person_add_alt,
                    variant: AppButtonVariant.secondary,
                    onPressed: _busy
                        ? null
                        : () {
                            final nav = Navigator.of(context);
                            final ctx = nav.context;
                            nav.pop();
                            showAddPlayerSheet(ctx, widget.club);
                          },
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text('Move a player', style: text.titleMedium),
                  const SizedBox(height: AppSpace.md),
                  field(
                    'Player',
                    dropdown<RosterPlayer>(
                      'roster_player',
                      'Player',
                      _player,
                      [
                        for (final p in widget.club.roster)
                          DropdownMenuItem(value: p, child: Text('${p.name} · ${p.position.toUpperCase()}${p.onLoan ? ' · on loan' : ''}', overflow: TextOverflow.ellipsis)),
                      ],
                      (p) => setState(() {
                        _player = p;
                        _error = null;
                      }),
                    ),
                  ),
                  field(
                    'Action',
                    Semantics(
                      identifier: 'roster_action',
                      child: SegmentedButton<RosterAction>(
                        segments: const [
                          ButtonSegment(value: RosterAction.transfer, label: Text('Transfer')),
                          ButtonSegment(value: RosterAction.loan, label: Text('Loan')),
                          ButtonSegment(value: RosterAction.release, label: Text('Release')),
                        ],
                        selected: {_action},
                        showSelectedIcon: false,
                        onSelectionChanged: _busy ? null : (s) => setState(() => _action = s.first),
                      ),
                    ),
                  ),
                  if (_action != RosterAction.release)
                    field(
                      'To club',
                      dropdown<String>(
                        'roster_to_club',
                        'To club',
                        _toClub,
                        [for (final c in others) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                        (v) => setState(() {
                          _toClub = v;
                          _error = null;
                        }),
                      ),
                    ),
                  field('Effective date', dateButton('roster_effective_date', _effective, false)),
                  if (_action == RosterAction.loan) field('Loan ends', dateButton('roster_loan_end', _loanEnd, true)),
                  AppTextField(id: 'roster_reason', label: 'Reason (optional)', controller: _reason, enabled: !_busy),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpace.md),
                    Text(_error!, style: text.bodyMedium!.copyWith(color: scheme.error)),
                  ],
                  const SizedBox(height: AppSpace.xl),
                  AppButton(
                    id: 'roster_submit',
                    label: switch (_action) {
                      RosterAction.transfer => 'Review transfer',
                      RosterAction.loan => 'Review loan',
                      RosterAction.release => 'Review release',
                    },
                    loading: _busy,
                    variant: _action == RosterAction.release ? AppButtonVariant.destructive : AppButtonVariant.primary,
                    onPressed: _submit,
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
