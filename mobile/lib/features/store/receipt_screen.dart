import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Opens a downloaded file in the phone's viewer (overridden in tests).
final openFileProvider = Provider<Future<void> Function(String path)>((ref) => (path) async {
      await OpenFilex.open(path, type: 'application/pdf');
    });

/// Signed receipt for an order: lines, totals, the server's HMAC-SHA256 signature and whether
/// it verifies, and the server-generated PDF (download, then open in the PDF viewer).
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  bool _saving = false;
  String? _savedPath;

  Future<void> _downloadPdf({required bool open}) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final opener = ref.read(openFileProvider);
    try {
      final bytes = await ref.read(apiClientProvider).getBytes('/api/v1/orders/${Uri.encodeComponent(widget.orderId)}/receipt.pdf');
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/receipt-${widget.orderId}.pdf');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() => _savedPath = file.path);
      if (open) {
        await opener(file.path);
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Receipt PDF saved on this phone.'), duration: AppMotion.snackbar));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception {
      messenger.showSnackBar(const SnackBar(content: Text("We couldn't save the PDF. Check the phone's free space and try again.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    final receipt = ref.watch(receiptProvider(widget.orderId));
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(
            children: [
              Expanded(child: Text(label, style: bold ? text.titleMedium : text.bodyLarge)),
              Text(value, style: (bold ? text.titleMedium!.copyWith(fontWeight: FontWeight.w800) : text.bodyLarge)!.copyWith(fontFeatures: AppFonts.tabular)),
            ],
          ),
        );

    return Scaffold(
      appBar: const TenantAppBar(title: 'Receipt'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'receipt_screen',
              container: true,
              child: PageBody(
                children: [
                  AsyncView<Order>(
                    id: 'receipt',
                    value: order,
                    onRetry: () => ref.invalidate(orderProvider(widget.orderId)),
                    builder: (o) {
                      final valid = receipt.value?['signature_valid'] == true;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: o.status == 'cancelled' || o.status == 'refunded'
                                ? StatusChip(kind: StatusKind.neutral, label: orderStatusLabel(o.status), icon: Icons.undo)
                                : const StatusChip(kind: StatusKind.success, label: 'Paid', icon: Icons.check),
                          ),
                          const SizedBox(height: AppSpace.md),
                          Semantics(header: true, child: Text('Thank you for your order', style: text.headlineSmall)),
                          const SizedBox(height: AppSpace.xs),
                          Text('Order ${o.id} · ${DateFormat('d MMM y, HH:mm').format(o.createdAt)}', style: text.bodyMedium!.copyWith(color: muted)),
                          const SizedBox(height: AppSpace.lg),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpace.lg),
                              child: Column(
                                children: [
                                  for (final l in o.lines) line('${l.productName}${l.label == 'Standard' ? '' : ' (${l.label})'} × ${l.quantity}', formatPrice(l.lineTotalMinor)),
                                  const Divider(),
                                  line('Subtotal', formatPrice(o.subtotalMinor)),
                                  if (o.discountMinor > 0) line('Discount', '− ${formatPrice(o.discountMinor)}'),
                                  line('Total paid', formatPrice(o.totalMinor), bold: true),
                                ],
                              ),
                            ),
                          ),
                          const SectionLabel('Integrity signature'),
                          if (receipt.hasValue)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: StatusChip(
                                kind: valid ? StatusKind.success : StatusKind.danger,
                                label: valid ? 'Signature verified by the server (HMAC-SHA256)' : 'Signature does not match',
                                icon: valid ? Icons.verified_outlined : Icons.gpp_bad_outlined,
                              ),
                            ),
                          const SizedBox(height: AppSpace.xs),
                          SelectableText(o.signature, style: text.bodySmall!.copyWith(letterSpacing: 0, fontFeatures: AppFonts.tabular)),
                          const SizedBox(height: AppSpace.xl),
                          AppButton(
                            id: 'receipt_open_pdf',
                            label: 'Open PDF receipt',
                            icon: Icons.picture_as_pdf_outlined,
                            loading: _saving,
                            onPressed: () => _downloadPdf(open: true),
                          ),
                          const SizedBox(height: AppSpace.md),
                          AppButton(
                            id: 'receipt_save_pdf',
                            label: _savedPath == null ? 'Download PDF to this phone' : 'PDF saved · download again',
                            icon: Icons.download_outlined,
                            variant: AppButtonVariant.secondary,
                            onPressed: _saving ? null : () => _downloadPdf(open: false),
                          ),
                          if (_savedPath != null) ...[
                            const SizedBox(height: AppSpace.sm),
                            Text('Saved to $_savedPath', style: text.bodySmall!.copyWith(letterSpacing: 0)),
                          ],
                          const SizedBox(height: AppSpace.md),
                          AppButton(
                            id: 'receipt_orders',
                            label: 'My orders',
                            variant: AppButtonVariant.text,
                            onPressed: () => context.push('/orders'),
                          ),
                          AppButton(
                            id: 'receipt_done',
                            label: 'Back to store',
                            variant: AppButtonVariant.text,
                            onPressed: () => context.go('/store'),
                          ),
                        ],
                      );
                    },
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
