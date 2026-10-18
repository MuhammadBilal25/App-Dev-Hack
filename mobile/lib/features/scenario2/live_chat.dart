import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import 'guest_api.dart';

/// Live chat for a match or co-stream room. Anyone can read; posting needs an account: the
/// server answers 403 GUEST_WRITE_FORBIDDEN for guests and the app offers sign-in (FR-4.4).
class LiveChat extends ConsumerStatefulWidget {
  const LiveChat({super.key, required this.room, required this.incoming});

  final String room;

  /// Messages pushed over the realtime feed while the screen is open.
  final List<Map<String, dynamic>> incoming;

  @override
  ConsumerState<LiveChat> createState() => _LiveChatState();
}

class _LiveChatState extends ConsumerState<LiveChat> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(apiClientProvider).post('/api/v1/chat', body: {'chat_room_id': widget.room, 'text': text}) as Map;
      _text.clear();
      if (r['accepted'] != true) messenger.showSnackBar(const SnackBar(content: Text('Your message was blocked by the chat filter.')));
    } on ApiException catch (e) {
      if (e.code == 'GUEST_WRITE_FORBIDDEN') {
        if (mounted) _askToSignIn();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _askToSignIn() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Semantics(
        identifier: 'progressive_auth_sheet',
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sign in to chat', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpace.sm),
              const Text('Watching is free. Chatting needs an account.'),
              const SizedBox(height: AppSpace.lg),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/login');
                },
                child: const Text('Sign in'),
              ),
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Not now')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(chatHistoryProvider(widget.room)).value ?? const [];
    final seen = <Object?>{};
    final messages = [...history, ...widget.incoming].where((m) => seen.add(m['sequence'] ?? m['message_id'])).toList();
    final signedIn = ref.watch(currentUserProvider) != null;
    return Semantics(
      identifier: 'live_chat',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Live chat', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpace.sm),
              if (messages.isEmpty) const Text('No messages yet.'),
              for (final m in messages.reversed.take(20).toList().reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${m['sender']}  ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    TextSpan(text: '${m['text']}'),
                  ])),
                ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'chat_input_field',
                      child: TextField(
                        controller: _text,
                        maxLength: 500,
                        decoration: InputDecoration(hintText: signedIn ? 'Say something…' : 'Sign in to chat', counterText: ''),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Semantics(
                    identifier: 'chat_send_btn',
                    button: true,
                    child: IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
