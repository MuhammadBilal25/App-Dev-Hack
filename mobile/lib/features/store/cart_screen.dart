import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/cart/cart.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import 'product_screen.dart';

/// Discount code typed in the cart, carried to checkout.
final cartDiscountProvider = NotifierProvider<CartDiscount, String>(CartDiscount.new);

class CartDiscount extends Notifier<String> {
  @override
  String build() => '';

  void set(String v) => state = v;
}

/// Server quote for the current cart (+ discount). Re-runs whenever the cart or code changes.
final cartQuoteProvider = FutureProvider<Quote?>((ref) async {
  final items = ref.watch(cartProvider);
  final code = ref.watch(cartDiscountProvider);
  if (items.isEmpty) return null;
  final body = await ref.read(apiClientProvider).post('/api/v1/cart/quote', body: {
    'items': [for (final i in items) {'variant_id': i.variantId, 'quantity': i.quantity, 'expected_unit_price_minor': i.unitPriceMinor}],
    if (code.isNotEmpty) 'discount_code': code,
  }) as Map<String, dynamic>;
  return Quote.fromJson(body);
});

/// Shopping cart: lines with photo, club, size/colour, quantity, server unit price and line
/// total; discount code; server-computed subtotal, discount and total. Problems (price changed,
/// low stock, no longer sold) are explained on the line, and checkout waits until they're fixed.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  late final _code = TextEditingController(text: ref.read(cartDiscountProvider));

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Accepts the server's current price for every changed line.
  Future<void> _acceptPrices(Quote q) async {
    final n = ref.read(cartProvider.notifier);
    for (final l in q.lines.where((l) => l.status == 'price_changed')) {
      await n.acceptPrice(l.variantId, l.unitPriceMinor);
    }
  }

  Future<void> _fixStock(Quote q) async {
    final n = ref.read(cartProvider.notifier);
    for (final l in q.lines) {
      if (l.status == 'unavailable' || l.status == 'out_of_stock') await n.remove(l.variantId);
      if (l.status == 'insufficient_stock') await n.setQuantity(l.variantId, l.availableStock);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final quote = ref.watch(cartQuoteProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const TenantAppBar(title: 'Your cart'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'cart_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(cartQuoteProvider.future),
                children: [
                  if (items.isEmpty)
                    EmptyState(
                      id: 'cart_empty',
                      icon: Icons.shopping_cart_outlined,
                      message: 'Your cart is empty. Browse the store to find shirts, caps and more.',
                      actionLabel: 'Go to the store',
                      onAction: () => context.go('/store'),
                    )
                  else ...[
                    for (final i in items) ...[
                      _CartLine(item: i, quote: quote.value?.lines.where((l) => l.variantId == i.variantId).firstOrNull),
                      const SizedBox(height: AppSpace.sm),
                    ],
                    const SizedBox(height: AppSpace.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: AppTextField(
                            id: 'cart_discount',
                            label: 'Discount code (optional)',
                            controller: _code,
                            hint: 'e.g. WELCOME10',
                            textInputAction: TextInputAction.done,
                            errorText: quote.value?.discountValid == false ? "That code isn't valid." : null,
                            onSubmitted: (v) => ref.read(cartDiscountProvider.notifier).set(v.trim().toUpperCase()),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Padding(
                          padding: EdgeInsets.only(bottom: quote.value?.discountValid == false ? 24 : 0),
                          child: SizedBox(
                            height: AppSize.inputHeight,
                            child: OutlinedButton(
                              onPressed: () => ref.read(cartDiscountProvider.notifier).set(_code.text.trim().toUpperCase()),
                              child: const Text('Apply'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    if (quote.isLoading && !quote.hasValue)
                      const Skeleton(rows: 2)
                    else if (quote.hasError)
                      ErrorBanner(
                        id: 'cart_quote_error',
                        message: quote.error is ApiException ? (quote.error as ApiException).message : "We couldn't check prices. Try again.",
                        onRetry: () => ref.invalidate(cartQuoteProvider),
                      )
                    else if (quote.value != null) ...[
                      _Summary(quote: quote.value!),
                      const SizedBox(height: AppSpace.lg),
                      if (quote.value!.lines.any((l) => l.status == 'price_changed'))
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.md),
                          child: AppButton(id: 'cart_accept_prices', label: 'Accept the new prices', variant: AppButtonVariant.secondary, onPressed: () => _acceptPrices(quote.value!)),
                        ),
                      if (quote.value!.lines.any((l) => ['unavailable', 'out_of_stock', 'insufficient_stock'].contains(l.status)))
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.md),
                          child: AppButton(id: 'cart_fix_stock', label: 'Remove or reduce unavailable items', variant: AppButtonVariant.secondary, onPressed: () => _fixStock(quote.value!)),
                        ),
                      AppButton(
                        id: 'cart_checkout',
                        label: quote.value!.canCheckout ? 'Checkout · ${formatPrice(quote.value!.totalMinor)}' : 'Fix the items above to check out',
                        variant: AppButtonVariant.cta,
                        icon: Icons.lock_outline,
                        onPressed: quote.value!.canCheckout ? () => context.push('/checkout') : null,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text('Prices and stock are checked again when you pay.', style: text.bodySmall!.copyWith(letterSpacing: 0), textAlign: TextAlign.center),
                    ],
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

class _CartLine extends ConsumerWidget {
  const _CartLine({required this.item, required this.quote});

  final CartItem item;
  final QuoteLine? quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final q = quote;
    final unit = q != null && q.unitPriceMinor > 0 ? q.unitPriceMinor : item.unitPriceMinor;
    final kind = q == null || q.ok ? null : (q.status == 'price_changed' || q.status == 'insufficient_stock' ? StatusKind.warning : StatusKind.danger);
    return Semantics(
      identifier: 'cart_line_${item.variantId}',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox.square(dimension: 64, child: ProductImageBox(imageUrl: item.imageUrl, category: 'apparel', iconSize: 36)),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.productName, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text([item.clubName, if (item.label != 'Standard') item.label].join(' · '), style: text.bodyMedium!.copyWith(color: muted), maxLines: 2),
                        const SizedBox(height: 2),
                        Text('${formatPrice(unit)} each', style: text.bodyMedium!.copyWith(fontFeatures: AppFonts.tabular)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove ${item.productName}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ref.read(cartProvider.notifier).remove(item.variantId),
                  ),
                ],
              ),
              if (kind != null) ...[
                const SizedBox(height: AppSpace.sm),
                Align(alignment: Alignment.centerLeft, child: StatusChip(kind: kind, label: q!.message ?? 'Needs attention', icon: Icons.info_outline)),
              ],
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  QuantityStepper(
                    id: 'cart_qty_${item.variantId}',
                    value: item.quantity,
                    max: Cart.maxQuantity,
                    onChanged: (v) => ref.read(cartProvider.notifier).setQuantity(item.variantId, v),
                  ),
                  const Spacer(),
                  Text(formatPrice(unit * item.quantity), style: text.titleMedium!.copyWith(fontFeatures: AppFonts.tabular)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(
            children: [
              Expanded(child: Text(label, style: bold ? text.titleMedium : text.bodyLarge)),
              Text(value, style: (bold ? text.titleMedium!.copyWith(fontWeight: FontWeight.w800) : text.bodyLarge)!.copyWith(fontFeatures: AppFonts.tabular)),
            ],
          ),
        );
    return Semantics(
      identifier: 'cart_summary',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            children: [
              line('Subtotal', formatPrice(quote.subtotalMinor)),
              if (quote.discountMinor > 0) line('Discount (${quote.discountCode}, ${quote.discountPercent}%)', '− ${formatPrice(quote.discountMinor)}'),
              const Divider(),
              line('Total', formatPrice(quote.totalMinor), bold: true),
            ],
          ),
        ),
      ),
    );
  }
}
