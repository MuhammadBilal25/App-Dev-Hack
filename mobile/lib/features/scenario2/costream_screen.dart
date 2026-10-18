import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../match/match_screen.dart' show sseClientFactoryProvider;
import 'guest_api.dart';
import 'hls_player.dart';
import 'live_channel.dart';
import 'live_chat.dart';

/// Co-Stream (Day 2, FR-3.3). Opened by nascon://stream/cs-session-*: the composite video, a
/// split view of up to 4 broadcasters (host marked) and the one shared chat room. Updates live
/// when the host hands over.
class CostreamScreen extends ConsumerStatefulWidget {
  const CostreamScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<CostreamScreen> createState() => _CostreamScreenState();
}

class _CostreamScreenState extends ConsumerState<CostreamScreen> {
  LiveChannel? _live;
  final _chat = <Map<String, dynamic>>[];

  String get _room => 'chat-${widget.sessionId}';

  @override
  void initState() {
    super.initState();
    _live = LiveChannel(
      baseUrl: ref.read(serverUrlProvider),
      channels: ['costream:${widget.sessionId}', 'chat:$_room'],
      clientFactory: ref.read(sseClientFactoryProvider),
      onEvent: (e) {
        if (!mounted) return;
        if (e['type'] == 'chat_message') {
          setState(() => _chat.add(Map<String, dynamic>.from(e['data'] as Map)));
        } else {
          ref.invalidate(guestCostreamProvider(widget.sessionId));
        }
      },
    )..open();
  }

  @override
  void dispose() {
    _live?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(guestCostreamProvider(widget.sessionId));
    final server = ref.watch(serverUrlProvider);
    final s = value.value;
    final notLive = value.error is ApiException && (value.error as ApiException).status == 404;
    final people = s == null ? const <Map<String, dynamic>>[] : (s['active_participants'] as List).map((p) => Map<String, dynamic>.from(p as Map)).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('Co-stream'),
      ),
      body: Semantics(
        identifier: 'costream_screen',
        container: true,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(guestCostreamProvider(widget.sessionId).future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              Text(widget.sessionId, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpace.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: HlsPlayer(
                  url: s == null ? null : mediaUrl(s['playback_url'] as String, server),
                  label: 'Co-stream video',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              if (notLive)
                const Card(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: Text('This co-stream has not started yet.')))
              else if (s != null) ...[
                Text(
                  s['status'] == 'terminated' ? 'Co-stream ended' : '${people.length} on air · layout ${s['layout']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpace.sm),
                _SplitView(people: people, host: s['active_host'] as String?),
              ],
              const SizedBox(height: AppSpace.md),
              LiveChat(room: (s?['chat_room_id'] as String?) ?? _room, incoming: _chat),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2x2 split view of the broadcasters (grid_4); one or two people fill the row.
class _SplitView extends StatelessWidget {
  const _SplitView({required this.people, required this.host});

  final List<Map<String, dynamic>> people;
  final String? host;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'costream_split_view',
      container: true,
      child: GridView.count(
        crossAxisCount: people.length <= 1 ? 1 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpace.sm,
        crossAxisSpacing: AppSpace.sm,
        childAspectRatio: people.length <= 1 ? 16 / 9 : 4 / 3,
        children: [
          for (final p in people)
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p['player_id'] == host ? scheme.primary : Colors.transparent, width: 2),
              ),
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam, size: 32),
                  const SizedBox(height: 4),
                  Text('${p['name']}', textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                  if (p['player_id'] == host) Text('Host', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
