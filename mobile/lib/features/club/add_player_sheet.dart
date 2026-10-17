import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/submit.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../data/models.dart';

const _roles = ['captain', 'vice_captain', 'starter', 'substitute'];
const _other = '__other__';

Future<void> showAddPlayerSheet(BuildContext context, ClubProfile club) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AddPlayerSheet(club: club),
  );
}

/// Club manager registers a new player. Queued as `player_add` and sent at once when online.
class AddPlayerSheet extends ConsumerStatefulWidget {
  const AddPlayerSheet({super.key, required this.club});

  final ClubProfile club;

  @override
  ConsumerState<AddPlayerSheet> createState() => _AddPlayerSheetState();
}

class _AddPlayerSheetState extends ConsumerState<AddPlayerSheet> {
  final _name = TextEditingController();
  final _customPosition = TextEditingController();
  String? _position;
  String _role = 'substitute';
  String? _nameError;
  String? _positionError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _position = widget.club.positions.isEmpty ? _other : widget.club.positions.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _customPosition.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final position = _position == _other ? _customPosition.text.trim() : _position ?? '';
    setState(() {
      _nameError = name.isEmpty ? "Enter the player's name." : null;
      _positionError = RegExp(r'^[A-Za-z0-9_ -]{1,20}$').hasMatch(position) ? null : 'Enter a position of up to 20 letters, like fw.';
    });
    if (_nameError != null || _positionError != null) return;
    final label = 'Add $name to ${widget.club.name}';
    final r = await ConfirmSheet.show(
      context,
      id: 'confirm_add_player',
      title: '$label?',
      message: '${position.toUpperCase()} · ${humanize(_role)}. The squad limit is checked when this syncs.',
      confirmLabel: 'Add player',
    );
    if (!r.confirmed || !mounted) return;
    setState(() => _busy = true);
    await submitAction(
      context,
      ref,
      type: 'player_add',
      baseVersion: 0,
      label: label,
      payload: {
        'club_id': widget.club.id,
        'body': {'name': name, 'position': position, 'role': _role, 'request_id': newClientId('add')},
      },
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'add_player_sheet',
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
                  Semantics(header: true, child: Text('Add player', style: text.titleLarge)),
                  const SizedBox(height: AppSpace.lg),
                  AppTextField(id: 'add_player_name', label: 'Name', controller: _name, errorText: _nameError, enabled: !_busy),
                  const SizedBox(height: AppSpace.lg),
                  Text('Position', style: text.titleSmall),
                  const SizedBox(height: AppSpace.xs + 2),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      for (final p in [...widget.club.positions, _other])
                        Semantics(
                          identifier: 'add_player_position_${p == _other ? 'other' : p}',
                          button: true,
                          selected: p == _position,
                          child: ChoiceChip(
                            label: Text(p == _other ? 'Other…' : p.toUpperCase()),
                            selected: p == _position,
                            showCheckmark: false,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: _busy ? null : (_) => setState(() => _position = p),
                          ),
                        ),
                    ],
                  ),
                  if (_position == _other) ...[
                    const SizedBox(height: AppSpace.md),
                    AppTextField(id: 'add_player_position_text', label: 'Other position', hint: 'e.g. fw', controller: _customPosition, enabled: !_busy),
                  ],
                  if (_positionError != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(_positionError!, style: text.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: AppSpace.lg),
                  Text('Role', style: text.titleSmall),
                  const SizedBox(height: AppSpace.xs + 2),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      for (final r in _roles)
                        Semantics(
                          identifier: 'add_player_role_$r',
                          button: true,
                          selected: r == _role,
                          child: ChoiceChip(
                            label: Text(humanize(r)),
                            selected: r == _role,
                            showCheckmark: false,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: _busy ? null : (_) => setState(() => _role = r),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xl),
                  AppButton(id: 'add_player_submit', label: 'Review new player', icon: Icons.person_add_alt, loading: _busy, onPressed: _submit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
