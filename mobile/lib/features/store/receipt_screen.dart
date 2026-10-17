import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';

/// Signed receipt after a successful checkout, with the server-made PDF saved on request.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.order, this.names = const {}});

  final Map<String, dynamic> order;
  /// Readable line names by variant id (e.g. "Home Jersey (L)"); the variant id is shown otherwise.
  final Map<String, String> names;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  bool _saving = false;
  String? _savedPath;

  Future<void> _savePdf() async {
    final receipt = widget.order['receipt'] as Map<String, dynamic>?;
    final b64 = receipt?['pdf_base64'] as String?;
    if (b64 == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/receipt-${widget.order['order_id']}.pdf');
      await file.writeAsBytes(base64Decode(b64));
      setState(() => _savedPath = file.path);
      messenger.showSnackBar(const SnackBar(content: Text('Receipt PDF saved on this phone.'), duration: AppMotion.snackbar));
    } on Exception {
      messenger.showSnackBar(const SnackBar(content: Text("We couldn't save the PDF. Check the phone's free space and try again.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final payload = (o['receipt'] as Map<String, dynamic>?)?['payload'] as Map<String, dynamic>? ?? const {};
    final signature = (o['receipt'] as Map<String, dynamic>?)?['signature'] as String? ?? '';
    final paidAt = DateTime.tryParse('${payload['paid_at']}')?.toLocal();
    final items = ((o['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    int minor(String k) => (o[k] as num?)?.toInt() ?? 0;

    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(
            children: [
              Expanded(child: Text(label, style: bold ? text.titleMedium : text.bodyLarge)),
              Text(value, style: bold ? text.titleMedium!.copyWith(fontWeight: FontWeight.w800) : text.bodyLarge),
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
                  const Align(alignment: Alignment.centerLeft, child: StatusChip(kind: StatusKind.success, label: 'Paid', icon: Icons.check)),
                  const SizedBox(height: AppSpace.md),
                  Semantics(header: true, child: Text('Thank you for your order', style: text.headlineSmall)),
                  const SizedBox(height: AppSpace.xs),
                  Text('Order ${o['order_id']}${paidAt == null ? '' : ' · ${DateFormat('d MMM y, HH:mm').format(paidAt)}'}', style: text.bodyMedium!.copyWith(color: muted)),
                  const SizedBox(height: AppSpace.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: Column(
                        children: [
                          for (final it in items)
                            line(
                              '${widget.names[it['variant_id']] ?? it['variant_id']} × ${it['quantity']}',
                              formatPrice(((it['unit_price_minor'] as num?)?.toInt() ?? 0) * ((it['quantity'] as num?)?.toInt() ?? 1)),
                            ),
                          const Divider(),
                          line('Subtotal', formatPrice(minor('subtotal_minor'))),
                          if (minor('discount_minor') > 0) line('Discount', '− ${formatPrice(minor('discount_minor'))}'),
                          line('Total paid', formatPrice(minor('total_minor')), bold: true),
                        ],
                      ),
                    ),
                  ),
                  const SectionLabel('Signature'),
                  Text(signature, style: text.bodySmall!.copyWith(letterSpacing: 0), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpace.xl),
                  AppButton(id: 'receipt_save_pdf', label: _savedPath == null ? 'Save PDF receipt' : 'PDF saved · save again', icon: Icons.picture_as_pdf_outlined, loading: _saving, onPressed: _savePdf),
                  if (_savedPath != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text('Saved to $_savedPath', style: text.bodySmall!.copyWith(letterSpacing: 0)),
                  ],
                  const SizedBox(height: AppSpace.md),
                  AppButton(
                    id: 'receipt_done',
                    label: 'Back to store',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).maybePop(),
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
