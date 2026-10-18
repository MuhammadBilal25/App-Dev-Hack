import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/cart/cart.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'cart_screen.dart';

/// The mock gateway's test cards (no real card details are ever asked for).
const mockCards = [
  (token: 'tok_success', label: 'Mock Visa •••• 4242', hint: 'Approves and captures the payment'),
  (token: 'tok_declined', label: 'Mock card •••• 0002', hint: 'Declined by the bank (test a failed payment)'),
  (token: 'tok_capture_fail', label: 'Mock card •••• 0119', hint: 'Approved, then capture fails (test a failure)'),
];

/// Checkout with the mock gateway: review the server-priced order, pick a test card, pay.
/// One order id per attempt keeps retries after a network error idempotent; a declined payment
/// releases the reserved stock and the next attempt gets a fresh id.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _Step { review, paying, done }

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _token = mockCards.first.token;
  String _orderId = _newOrderId();
  _Step _step = _Step.review;
  String? _error;

  static String _newOrderId() {
    final r = Random.secure();
    return 'ord-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  Future<void> _pay(Quote q) async {
    final confirm = await ConfirmSheet.show(
      context,
      id: 'confirm_pay',
      title: 'Pay ${formatPrice(q.totalMinor)}?',
      message: '${q.lines.length} ${q.lines.length == 1 ? 'item' : 'items'} with ${mockCards.firstWhere((c) => c.token == _token).label}. This is a test payment: no real money moves.',
      confirmLabel: 'Pay',
      variant: AppButtonVariant.cta,
    );
    if (!confirm.confirmed || !mounted) return;
    setState(() {
      _step = _Step.paying;
      _error = null;
    });
    final items = ref.read(cartProvider);
    final code = ref.read(cartDiscountProvider);
    try {
      final body = await ref.read(apiClientProvider).post('/api/v1/checkout', body: {
        'order_id': _orderId,
        'items': [for (final i in items) {'variant_id': i.variantId, 'quantity': i.quantity}],
        if (code.isNotEmpty) 'discount_code': code,
        'payment': {'token': _token},
      }) as Map<String, dynamic>;
      await ref.read(cartProvider.notifier).clear();
      ref.read(cartDiscountProvider.notifier).set('');
      ref.invalidate(catalogueProvider);
      ref.invalidate(ordersProvider('mine'));
      if (!mounted) return;
      setState(() => _step = _Step.done);
      context.pushReplacement('/receipt/${Uri.encodeComponent(body['order_id'] as String)}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.review;
        _error = e.message;
        // A network failure may have reached the server: retry with the same id. Anything the
        // server answered (declined, out of stock...) is final for this id.
        if (!e.isNetwork) _orderId = _newOrderId();
      });
      if (e.code == 'OUT_OF_STOCK' || e.code == 'PRODUCT_UNAVAILABLE') ref.invalidate(cartQuoteProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = ref.watch(cartQuoteProvider);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: const TenantAppBar(title: 'Checkout'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'checkout_screen',
              container: true,
              child: PageBody(
                children: [
                  _Steps(step: _step),
                  const SizedBox(height: AppSpace.lg),
                  AsyncView<Quote?>(
                    id: 'checkout_quote',
                    value: quote,
                    onRetry: () => ref.invalidate(cartQuoteProvider),
                    builder: (q) {
                      if (q == null) {
                        return Text('Your cart is empty.', style: text.bodyLarge);
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionLabel('Order summary'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpace.lg),
                              child: Column(
                                children: [
                                  for (final l in q.lines)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${l.productName}${l.label == 'Standard' ? '' : ' (${l.label})'} × ${l.quantity}',
                                              style: text.bodyLarge,
                                            ),
                                          ),
                                          Text(formatPrice(l.lineTotalMinor), style: text.bodyLarge!.copyWith(fontFeatures: AppFonts.tabular)),
                                        ],
                                      ),
                                    ),
                                  const Divider(),
                                  _line(text, 'Subtotal', formatPrice(q.subtotalMinor)),
                                  if (q.discountMinor > 0) _line(text, 'Discount (${q.discountCode})', '− ${formatPrice(q.discountMinor)}'),
                                  _line(text, 'Total to pay', formatPrice(q.totalMinor), bold: true),
                                ],
                              ),
                            ),
                          ),
                          const SectionLabel('Payment method'),
                          Text('Test cards for the mock payment gateway. Never enter a real card.', style: text.bodyMedium!.copyWith(color: muted)),
                          const SizedBox(height: AppSpace.sm),
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: RadioGroup<String>(
                              groupValue: _token,
                              onChanged: (v) => setState(() => _token = v ?? _token),
                              child: Column(
                                children: [
                                  for (final c in mockCards)
                                    Semantics(
                                      identifier: 'pay_${c.token}',
                                      child: RadioListTile<String>(
                                        value: c.token,
                                        enabled: _step == _Step.review,
                                        title: Text(c.label),
                                        subtitle: Text(c.hint),
                                        secondary: const Icon(Icons.credit_card),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpace.lg),
                            ErrorBanner(id: 'checkout_error', message: _error!),
                          ],
                          if (!q.canCheckout) ...[
                            const SizedBox(height: AppSpace.lg),
                            const ErrorBanner(id: 'checkout_blocked', message: 'Some items changed or sold out. Go back to the cart to fix them.'),
                          ],
                          const SizedBox(height: AppSpace.xl),
                          AppButton(
                            id: 'checkout_pay',
                            label: 'Pay ${formatPrice(q.totalMinor)}',
                            icon: Icons.lock_outline,
                            variant: AppButtonVariant.cta,
                            loading: _step == _Step.paying,
                            onPressed: q.canCheckout ? () => _pay(q) : null,
                          ),
                          const SizedBox(height: AppSpace.md),
                          AppButton(
                            id: 'checkout_cancel',
                            label: 'Cancel checkout',
                            variant: AppButtonVariant.secondary,
                            onPressed: _step == _Step.paying ? null : () => context.pop(),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Text('Cancelling returns you to your cart. Nothing is charged.', style: text.bodySmall!.copyWith(letterSpacing: 0), textAlign: TextAlign.center),
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

  Widget _line(TextTheme text, String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(
          children: [
            Expanded(child: Text(label, style: bold ? text.titleMedium : text.bodyLarge)),
            Text(value, style: (bold ? text.titleMedium!.copyWith(fontWeight: FontWeight.w800) : text.bodyLarge)!.copyWith(fontFeatures: AppFonts.tabular)),
          ],
        ),
      );
}

class _Steps extends StatelessWidget {
  const _Steps({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const labels = ['Cart', 'Payment', 'Receipt'];
    final current = switch (step) {
      _Step.review => 1,
      _Step.paying => 1,
      _Step.done => 2,
    };
    return Semantics(
      label: 'Step ${current + 1} of 3: ${labels[current]}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) Expanded(child: Divider(color: i <= current ? scheme.primary : scheme.outlineVariant, thickness: 2)),
            CircleAvatar(
              radius: 14,
              backgroundColor: i <= current ? scheme.primary : scheme.surfaceContainerHigh,
              foregroundColor: i <= current ? scheme.onPrimary : scheme.onSurfaceVariant,
              child: i < current ? const Icon(Icons.check, size: 16) : Text('${i + 1}', style: text.labelMedium!.copyWith(color: i <= current ? scheme.onPrimary : null)),
            ),
            const SizedBox(width: AppSpace.xs),
            Text(labels[i], style: text.labelMedium),
          ],
        ],
      ),
    );
  }
}
