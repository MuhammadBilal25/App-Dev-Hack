import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import 'guest_api.dart';
import 'hls_player.dart';

/// Creator tools (FR-3.2 / FR-3.3) for a signed-in player: get a signed stream key for
/// OBS / FFmpeg / Larix (RTMP) or WebRTC WHIP, preview the playback, revoke it (the media server
/// drops the ingest at once), and start a 4-way co-stream.
class GoLiveScreen extends ConsumerStatefulWidget {
  const GoLiveScreen({super.key});

  @override
  ConsumerState<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends ConsumerState<GoLiveScreen> {
  Map<String, dynamic>? _key;
  bool _busy = false;

  static const _squad = ['player-alpha-1', 'player-alpha-2', 'player-beta-1', 'player-beta-2'];

  Future<void> _call(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keyAction(String playerId, String action) => _call(() async {
        final r = await ref.read(apiClientProvider).post('/audit/v1/stream/key', body: {'action': action, 'player_id': playerId, 'label': 'Mobile'});
        setState(() => _key = Map<String, dynamic>.from(r as Map));
      });

  Future<void> _startCostream(String playerId) => _call(() async {
        final participants = [playerId, ..._squad.where((p) => p != playerId)].take(4).toList();
        await ref.read(apiClientProvider).post('/audit/v1/costream/session', body: {
          'session_id': 'cs-session-101',
          'host_player_id': playerId,
          'participants': participants,
          'layout': 'grid_4',
          'simulate_host_drop': false,
        });
        if (mounted) context.push('/live/costream/cs-session-101');
      });

  Widget _copyRow(String label, String value) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: SelectableText(value),
        trailing: IconButton(
          tooltip: 'Copy $label',
          icon: const Icon(Icons.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final server = ref.watch(serverUrlProvider);
    final playerId = user?.playerId;
    final k = _key;
    final active = k != null && k['status'] == 'active';

    return Scaffold(
      appBar: AppBar(title: const Text('Go live')),
      body: Semantics(
        identifier: 'go_live_screen',
        container: true,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (playerId == null)
              const Card(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: Text('Only players can broadcast. Sign in with a player account.')))
            else ...[
              Text('Broadcast from OBS, FFmpeg or a phone RTMP app (Larix) with your private stream key.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _keyAction(playerId, k == null ? 'generate' : 'rotate'),
                    icon: const Icon(Icons.key),
                    label: Text(k == null ? 'Get stream key' : 'New key (rotate)'),
                  ),
                  if (active)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _keyAction(playerId, 'revoke'),
                      icon: const Icon(Icons.block),
                      label: const Text('Stop and revoke'),
                    ),
                ],
              ),
              if (k != null) ...[
                const SizedBox(height: AppSpace.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(active ? 'Key is active' : 'Key revoked: ingest was cut', style: Theme.of(context).textTheme.titleMedium),
                        if (active) ...[
                          _copyRow('RTMP server', mediaUrl('${k['ingest_endpoints']['rtmp']}', server).replaceFirst('/${k['stream_key']}', '')),
                          _copyRow('Stream key', '${k['stream_key']}'),
                          _copyRow('WebRTC (WHIP)', mediaUrl('${k['ingest_endpoints']['webrtc']}', server)),
                          const SizedBox(height: AppSpace.sm),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: HlsPlayer(url: mediaUrl('${k['playback_url']}', server), label: 'Your stream preview'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              Text('Squad co-stream', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpace.sm),
              const Text('Start a 4-way co-stream (cs-session-101) with your squad. Viewers get one shared chat.'),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _startCostream(playerId),
                icon: const Icon(Icons.grid_view),
                label: const Text('Start co-stream'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
