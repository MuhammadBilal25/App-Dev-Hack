import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../theme/tokens.dart';
import 'app_button.dart';
import 'error_banner.dart';

/// A photo chosen on the phone, before upload.
class PickedImage {
  const PickedImage(this.bytes, this.contentType, this.name);

  final Uint8List bytes;
  final String contentType;
  final String name;
}

const maxImageBytes = 5 * 1024 * 1024;
const _types = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp'};

String? contentTypeFor(String name, String? reported) {
  if (reported != null && _types.containsValue(reported)) return reported;
  final ext = name.split('.').last.toLowerCase();
  return _types[ext];
}

/// Opens the gallery (overridden in tests). Large photos are scaled down on the phone first.
final imagePickerProvider = Provider<Future<PickedImage?> Function()>((ref) => () async {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
      if (x == null) return null;
      final type = contentTypeFor(x.name, x.mimeType) ?? 'application/octet-stream';
      return PickedImage(await x.readAsBytes(), type, x.name);
    });

/// Checks a picked photo before uploading; returns a plain-language problem or null.
String? checkImage(PickedImage img) {
  if (!_types.containsValue(img.contentType)) return 'Only JPEG, PNG and WebP photos can be uploaded.';
  if (img.bytes.length > maxImageBytes) return 'That photo is ${(img.bytes.length / 1048576).toStringAsFixed(1)} MB. Choose one under 5 MB.';
  if (img.bytes.isEmpty) return 'That file is empty. Choose another photo.';
  return null;
}

/// Pick → preview → upload with a progress bar and readable errors. [path] is the upload
/// endpoint; [onUploaded] receives the server response.
class ImageUploadPanel extends ConsumerStatefulWidget {
  const ImageUploadPanel({super.key, required this.id, required this.path, required this.onUploaded, this.buttonLabel = 'Add photo'});

  final String id;
  final String path;
  final String buttonLabel;
  final ValueChanged<Map<String, dynamic>> onUploaded;

  @override
  ConsumerState<ImageUploadPanel> createState() => _ImageUploadPanelState();
}

class _ImageUploadPanelState extends ConsumerState<ImageUploadPanel> {
  PickedImage? _picked;
  double? _progress;
  String? _error;

  Future<void> _pick() async {
    final img = await ref.read(imagePickerProvider)();
    if (img == null || !mounted) return;
    setState(() {
      _picked = img;
      _error = checkImage(img);
      _progress = null;
    });
  }

  Future<void> _upload() async {
    final img = _picked;
    if (img == null || checkImage(img) != null) return;
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final body = await ref.read(apiClientProvider).upload(widget.path, img.bytes, img.contentType, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _picked = null;
        _progress = null;
      });
      widget.onUploaded(body);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final img = _picked;
    final uploading = _progress != null;
    return Semantics(
      identifier: widget.id,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (img != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(
                aspectRatio: 1.6,
                child: Image.memory(
                  img.bytes,
                  fit: BoxFit.cover,
                  semanticLabel: 'Preview of ${img.name}',
                  errorBuilder: (context, error, stack) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: const Text('Preview not available. The server checks the file when you upload.'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text('${img.name} · ${(img.bytes.length / 1024).round()} KB', style: text.bodySmall!.copyWith(letterSpacing: 0)),
            if (uploading) ...[
              const SizedBox(height: AppSpace.sm),
              Semantics(
                label: 'Uploading, ${(_progress! * 100).round()} percent',
                child: LinearProgressIndicator(value: _progress),
              ),
            ],
            const SizedBox(height: AppSpace.sm),
          ],
          if (_error != null) ...[
            ErrorBanner(id: '${widget.id}_error', message: _error!),
            const SizedBox(height: AppSpace.sm),
          ],
          Row(
            children: [
              Expanded(
                child: AppButton(
                  id: '${widget.id}_pick',
                  label: img == null ? widget.buttonLabel : 'Choose another',
                  icon: Icons.photo_library_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: uploading ? null : _pick,
                ),
              ),
              if (img != null) ...[
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: AppButton(
                    id: '${widget.id}_upload',
                    label: 'Upload',
                    icon: Icons.cloud_upload_outlined,
                    loading: uploading,
                    onPressed: _error == null ? _upload : null,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
