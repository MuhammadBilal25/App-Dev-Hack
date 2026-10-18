import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/tokens.dart';
import 'deep_link.dart';
import 'guest_api.dart';

/// Native QR scanner (FR-4.1). Understands nascon:// links, dynamic short links
/// (http://host:8080/q/{code}, resolved through the server's 302 so the target follows the live
/// match state) and Guest Web Player links. A paste box covers emulators without a camera.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _manual = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    _manual.dispose();
    super.dispose();
  }

  /// Turns any scanned text into an app route, or null.
  Future<String?> _resolve(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme == 'nascon') return deepLinkTarget(uri);
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final direct = webRouteTarget(uri.path);
    if (direct != null) return direct;
    if (!uri.path.startsWith('/q/')) return null;
    // Printed codes say "localhost"; ask the API this app is connected to instead.
    final server = Uri.parse(ref.read(serverUrlProvider));
    final target = uri.replace(scheme: server.scheme, host: server.host, port: server.hasPort ? server.port : uri.port);
    final client = http.Client();
    try {
      final req = http.Request('GET', target)..followRedirects = false;
      final res = await client.send(req).timeout(const Duration(seconds: 10));
      final location = res.headers['location'];
      return location == null ? null : webRouteTarget(location);
    } finally {
      client.close();
    }
  }

  Future<void> _handle(String raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? route;
    try {
      route = await _resolve(raw);
    } catch (_) {
      route = null;
    }
    if (!mounted) return;
    if (route == null) {
      setState(() {
        _busy = false;
        _error = 'That code is not a NaSCon link.';
      });
      return;
    }
    await _scanner.stop();
    if (!mounted) return;
    context.pushReplacement(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a QR code')),
      body: Semantics(
        identifier: 'qr_scan_screen',
        container: true,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: MobileScanner(
                  controller: _scanner,
                  onDetect: (capture) {
                    final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
                    if (value != null) _handle(value);
                  },
                  errorBuilder: (context, error, child) => _CameraError(
                    error: error,
                    onRetry: () async {
                      await _scanner.stop();
                      await _scanner.start();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            const Text('Point the camera at a match, club, player or co-stream poster.'),
            if (_busy) const Padding(padding: EdgeInsets.only(top: AppSpace.md), child: LinearProgressIndicator()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.md),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: AppSpace.xl),
            Semantics(
              identifier: 'qr_manual_link',
              child: TextField(
                controller: _manual,
                decoration: const InputDecoration(labelText: 'Or paste a link', hintText: 'http://localhost:8080/q/m1-live'),
                onSubmitted: _handle,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            FilledButton(onPressed: () => _handle(_manual.text), child: const Text('Open')),
          ],
        ),
      ),
    );
  }
}

/// Says why the camera did not open (permission, no camera, already in use) and offers a retry.
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});

  final MobileScannerException error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final reason = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => 'Camera permission is off. Allow it in Settings > Apps > huddle > Permissions, then tap Try again.',
      MobileScannerErrorCode.unsupported => 'This device has no usable camera. Paste the link below.',
      _ => 'Camera could not start (${error.errorCode.name}${error.errorDetails?.message == null ? '' : ': ${error.errorDetails!.message}'}).',
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 40),
              const SizedBox(height: AppSpace.sm),
              Text(reason, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.md),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
