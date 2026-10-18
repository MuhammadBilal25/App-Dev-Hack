import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// HLS player (ExoPlayer on Android). Shows a calm placeholder until the stream is on air, so a
/// match page opened before kick-off never looks broken.
class HlsPlayer extends StatefulWidget {
  const HlsPlayer({super.key, required this.url, this.label = 'Live video'});

  final String? url;
  final String label;

  @override
  State<HlsPlayer> createState() => _HlsPlayerState();
}

class _HlsPlayerState extends State<HlsPlayer> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(HlsPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _c?.dispose();
      _c = null;
      _failed = false;
      _open();
    }
  }

  Future<void> _open() async {
    final url = widget.url;
    if (url == null) return;
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url), formatHint: VideoFormat.hls);
      _c = c;
      await c.initialize();
      await c.setVolume(0);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      // No stream yet, or no video plugin (tests): keep the placeholder.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && !_failed && c.value.isInitialized;
    return Semantics(
      identifier: 'guest_video_player',
      label: widget.label,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: ready
              ? FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_circle_outline, size: 56, color: Colors.white70),
                      const SizedBox(height: 8),
                      Text(
                        widget.url == null ? 'No stream for this page' : 'Waiting for the live stream',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
