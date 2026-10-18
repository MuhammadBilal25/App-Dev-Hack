import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../match/match_screen.dart' show sseClientFactoryProvider;
import 'guest_api.dart';
import 'hls_player.dart';
import 'live_channel.dart';
import 'live_chat.dart';

/// Match Live (Day 2). Opened by nascon://entity/match-*, a scanned QR or a fixture. Works
/// without an account: video, live score (pushed over SSE), pinned merch and chat.
class LiveMatchScreen extends ConsumerStatefulWidget {
  const LiveMatchScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<LiveMatchScreen> createState() => _LiveMatchScreenState();
}

class _LiveMatchScreenState extends ConsumerState<LiveMatchScreen> {
  LiveChannel? _live;
  final _chat = <Map<String, dynamic>>[];

  String get _room => 'chat-${widget.matchId}';

  @override
  void initState() {
    super.initState();
    _live = LiveChannel(
      baseUrl: ref.read(serverUrlProvider),
      channels: ['match:${widget.matchId}', 'chat:$_room'],
      clientFactory: ref.read(sseClientFactoryProvider),
      onEvent: (e) {
        if (!mounted) return;
        if (e['type'] == 'chat_message') {
          setState(() => _chat.add(Map<String, dynamic>.from(e['data'] as Map)));
        } else {
          ref.invalidate(guestMatchProvider(widget.matchId));
        }
      },
    )..open();
  }

  @override
  void dispose() {
    _live?.close();
    super.dispose();
  }

  static const _statusLabel = {
    'in_progress': 'LIVE',
    'upcoming': 'Upcoming',
    'completed': 'Full time',
    'postponed': 'Postponed',
    'cancelled': 'Cancelled',
    'abandoned': 'Abandoned',
  };

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(guestMatchProvider(widget.matchId));
    final server = ref.watch(serverUrlProvider);
    final m = value.value;
    final status = m?['status'] as String?;
    final playback = m == null ? null : (status == 'completed' ? m['vod_url'] : m['playback_url']) as String?;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Text(m == null ? 'Match' : '${m['home']['name']} vs ${m['away']['name']}', overflow: TextOverflow.ellipsis),
      ),
      body: Semantics(
        identifier: 'match_live_screen',
        container: true,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(guestMatchProvider(widget.matchId).future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              if (value.hasError && m == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Text('Could not load match ${widget.matchId}. Pull down to try again.'),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    HlsPlayer(url: playback == null ? null : mediaUrl(playback, server), label: 'Live match video'),
                    if (m != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Center(child: _ScoreBanner(match: m, statusLabel: _statusLabel[status] ?? status ?? '')),
                      ),
                  ],
                ),
              ),
              if (status == 'upcoming') const _Note('This match has not started yet. The stream starts at kick-off.'),
              if (status == 'postponed' || status == 'cancelled' || status == 'abandoned') _Note('This match is $status.'),
              const SizedBox(height: AppSpace.md),
              if (m != null && m['pinned_product'] != null) _PinnedMerch(product: Map<String, dynamic>.from(m['pinned_product'] as Map)),
              const SizedBox(height: AppSpace.md),
              LiveChat(room: (m?['chat_room_id'] as String?) ?? _room, incoming: _chat),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreBanner extends StatelessWidget {
  const _ScoreBanner({required this.match, required this.statusLabel});

  final Map<String, dynamic> match;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
    return Semantics(
      identifier: 'live_score_banner',
      label: 'Score ${match['score_text']}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusLabel == 'LIVE')
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFC62828), borderRadius: BorderRadius.circular(4)),
                child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            Flexible(child: Text('${match['home']['name']}', style: white, overflow: TextOverflow.ellipsis)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('${match['score_text']}', style: white.copyWith(fontSize: 20)),
            ),
            Flexible(child: Text('${match['away']['name']}', style: white, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class _PinnedMerch extends StatelessWidget {
  const _PinnedMerch({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final variants = (product['variants'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
    final pinned = variants.firstWhere((v) => v['variant_id'] == product['pinned_variant_id'], orElse: () => variants.first);
    final price = (pinned['price_minor'] as num) / 100;
    return Semantics(
      identifier: 'pinned_merch_card',
      container: true,
      child: Card(
        child: ListTile(
          minTileHeight: 64,
          leading: const Icon(Icons.checkroom),
          title: Text('${product['name']} (${pinned['size']})'),
          subtitle: Text('PKR ${price.toStringAsFixed(2)} · Pinned for this match'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/product/${product['product_id']}'),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: Card(child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(text))),
      );
}
