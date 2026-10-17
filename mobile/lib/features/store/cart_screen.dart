import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/brand/jersey_icon.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import 'cart.dart';

/// The cart (Section 8.2 Store): lines with quantities, discount code, one mock-card checkout of
/// everything in it, then the receipt.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _discount = TextEditingController();
  bool _paying = false;
  String? _error;
  String? _discountError;

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  Future<void> _checkout(List<CartLine> lines, int subtotal) async {
    final confirm = await ConfirmSheet.show(
      context,
      id: 'confirm_cart_pay',
      title: 'Pay ${formatPrice(subtotal)}?',
      message: '${lines.length == 1 ? '1 item' : '${lines.length} items'} in your cart. Your mock card is charged once; '
          'a discount code is applied by the server. A receipt opens next.',
      confirmLabel: 'Pay',
      variant: AppButtonVariant.cta,
    );
    if (!confirm.confirmed || !mounted) return;
    setState(() {
      _paying = true;
      _error = null;
      _discountError = null;
    });
    try {
      final order = await checkoutLines(ref, lines, discountCode: _discount.text);
      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      context.pushReplacement('/receipt', extra: receiptExtra(order, lines));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => e.code == 'INVALID_DISCOUNT_CODE' ? _discountError = e.message : _error = e.message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final subtotal = lines.fold(0, (n, l) => n + l.totalMinor);
    final count = lines.fold(0, (n, l) => n + l.quantity);

    return Scaffold(
      appBar: const TenantAppBar(title: 'Cart'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'cart_screen',
              container: true,
              child: PageBody(
                children: [
                  if (lines.isEmpty)
                    EmptyState(
                      id: 'cart_empty',
                      icon: Icons.shopping_bag_outlined,
                      message: 'Your cart is empty. Browse the club store.',
                      actionLabel: 'Back to store',
                      onAction: () => context.pop(),
                    )
                  else ...[
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < lines.length; i++) ...[
                            if (i > 0) const Divider(),
                            _CartRow(line: lines[i], enabled: !_paying),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Row(
                      children: [
                        Expanded(child: Text('Subtotal · $count ${count == 1 ? 'item' : 'items'}', style: text.bodyLarge)),
                        Text(formatPrice(subtotal), style: text.titleMedium!.copyWith(fontWeight: FontWeight.w800, fontFeatures: AppFonts.tabular)),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    AppTextField(
                      id: 'cart_discount',
                      label: 'Discount code (optional)',
                      controller: _discount,
                      hint: 'e.g. WELCOME10',
                      errorText: _discountError,
                      enabled: !_paying,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpace.lg),
                      ErrorBanner(id: 'cart_error', message: _error!),
                    ],
                    const SizedBox(height: AppSpace.xl),
                    Semantics(
                      identifier: 'cart_pay',
                      button: true,
                      enabled: !_paying,
                      label: 'Pay with mock card · ${formatPrice(subtotal)}',
                      excludeSemantics: true,
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _paying ? null : () => _checkout(lines, subtotal),
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.tertiary,
                            foregroundColor: scheme.onTertiary,
                            disabledBackgroundColor: _paying ? scheme.tertiary : null,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                          ),
                          child: _paying
                              ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onTertiary))
                              : Row(
                                  children: [
                                    const Expanded(child: Text('Pay with mock card', maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text(formatPrice(subtotal)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends ConsumerWidget {
  const _CartRow({required this.line, required this.enabled});

  final CartLine line;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final cart = ref.read(cartProvider.notifier);
    final v = line.variant;
    final canAdd = enabled && line.quantity < Cart.limitFor(v);
    final id = v.id;

    Widget stepButton(String sid, IconData icon, String label, VoidCallback? onTap) => Semantics(
          identifier: sid,
          button: true,
          label: label,
          excludeSemantics: true,
          child: IconButton(
            tooltip: label,
            onPressed: onTap,
            style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
            icon: Icon(icon, size: 20),
          ),
        );

    return Semantics(
      identifier: 'cart_line_$id',
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: JerseyIcon(size: 30, color: scheme.primary),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.product.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text('Size ${v.size} · ${formatPrice(v.priceMinor)} each', style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text(formatPrice(line.totalMinor), style: text.titleMedium!.copyWith(fontFeatures: AppFonts.tabular)),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                stepButton('cart_minus_$id', Icons.remove, 'One fewer ${v.size}', enabled ? () => cart.setQuantity(id, line.quantity - 1) : null),
                SizedBox(
                  width: 40,
                  child: Text('${line.quantity}', textAlign: TextAlign.center, style: text.titleMedium!.copyWith(fontFeatures: AppFonts.tabular)),
                ),
                stepButton('cart_plus_$id', Icons.add, 'One more ${v.size}', canAdd ? () => cart.setQuantity(id, line.quantity + 1) : null),
                const Spacer(),
                Semantics(
                  identifier: 'cart_remove_$id',
                  button: true,
                  child: TextButton(onPressed: enabled ? () => cart.remove(id) : null, child: const Text('Remove')),
                ),
              ],
            ),
            if (!canAdd && enabled)
              Text(
                v.stock <= line.quantity ? 'Only ${v.stock} in stock.' : 'Up to $maxLineQuantity per order.',
                style: text.bodySmall!.copyWith(letterSpacing: 0),
              ),
          ],
        ),
      ),
    );
  }
}
