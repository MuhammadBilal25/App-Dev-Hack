import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

Future<void> showProductSheet(BuildContext context, Product product) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ProductSheet(product: product),
  );
}

/// Variant picker + discount + mock-card checkout (Task B).
class ProductSheet extends ConsumerStatefulWidget {
  const ProductSheet({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends ConsumerState<ProductSheet> {
  final _discount = TextEditingController();
  Variant? _selected;
  bool _paying = false;
  String? _error;
  String? _discountError;

  @override
  void initState() {
    super.initState();
    final inStock = widget.product.variants.where((v) => v.stock > 0);
    _selected = inStock.isEmpty ? null : inStock.first;
  }

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  static String _orderId() {
    final r = Random.secure();
    return 'ord-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  Future<void> _pay() async {
    final v = _selected;
    final user = ref.read(currentUserProvider);
    if (v == null || user == null) return;
    final confirm = await ConfirmSheet.show(
      context,
      id: 'confirm_pay',
      title: 'Pay ${formatPrice(v.priceMinor)}?',
      message: '${widget.product.name}, size ${v.size}. Your mock card is charged once; a receipt opens next.',
      confirmLabel: 'Pay',
      variant: AppButtonVariant.cta,
    );
    if (!confirm.confirmed || !mounted) return;
    setState(() {
      _paying = true;
      _error = null;
      _discountError = null;
    });
    final code = _discount.text.trim().toUpperCase();
    try {
      final body = await ref.read(apiClientProvider).post('/audit/v1/checkout', body: {
        'order_id': _orderId(),
        'customer_id': user.id,
        'items': [
          {'variant_id': v.id, 'quantity': 1},
        ],
        if (code.isNotEmpty) 'discount_code': code,
        'payment': {'token': 'tok_success'},
      }) as Map<String, dynamic>;
      ref.invalidate(catalogueProvider);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push('/receipt', extra: {'order': body, 'product': widget.product, 'variant': v});
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'INVALID_DISCOUNT_CODE') {
          _discountError = e.message;
        } else {
          _error = e.message;
        }
      });
      if (e.code == 'OUT_OF_STOCK') ref.invalidate(catalogueProvider);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final v = _selected;
    return Semantics(
      identifier: 'product_sheet',
      container: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(header: true, child: Text(p.name, style: text.titleLarge)),
                  const SizedBox(height: AppSpace.xs),
                  Text(p.clubName.isEmpty ? p.description : '${p.clubName} · ${p.description}', style: text.bodyMedium!.copyWith(color: muted)),
                  const SizedBox(height: AppSpace.lg),
                  Text(v == null ? formatPrice(p.fromPriceMinor) : formatPrice(v.priceMinor), style: text.headlineSmall),
                  const SizedBox(height: AppSpace.lg),
                  Text('Size', style: text.titleSmall),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [for (final variant in p.variants) _SizeButton(variant: variant, selected: variant == v, onTap: () => setState(() => _selected = variant))],
                  ),
                  if (v != null) ...[
                    const SizedBox(height: AppSpace.md),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: v.stock == 1
                          ? const StatusChip(kind: StatusKind.warning, label: 'Last one!', icon: Icons.local_fire_department_outlined)
                          : StatusChip(kind: StatusKind.success, label: '${v.stock} in stock', icon: Icons.check),
                    ),
                  ],
                  const SizedBox(height: AppSpace.lg),
                  AppTextField(
                    id: 'product_discount',
                    label: 'Discount code (optional)',
                    controller: _discount,
                    hint: 'e.g. WELCOME10',
                    errorText: _discountError,
                    textInputAction: TextInputAction.done,
                    enabled: !_paying,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpace.lg),
                    ErrorBanner(id: 'checkout_error', message: _error!),
                  ],
                  const SizedBox(height: AppSpace.xl),
                  AppButton(
                    id: 'product_pay',
                    variant: AppButtonVariant.cta,
                    loading: _paying,
                    label: v == null ? 'Sold out · pick another product' : 'Pay with mock card · ${formatPrice(v.priceMinor)}',
                    icon: Icons.credit_card,
                    onPressed: v == null ? null : _pay,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeButton extends StatelessWidget {
  const _SizeButton({required this.variant, required this.selected, required this.onTap});

  final Variant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final soldOut = variant.stock <= 0;
    final stockText = soldOut ? 'Sold out' : variant.stock == 1 ? 'Last one' : '${variant.stock} left';
    return Semantics(
      identifier: 'size_${variant.size.toLowerCase()}',
      button: true,
      selected: selected,
      enabled: !soldOut,
      label: 'Size ${variant.size}, $stockText',
      excludeSemantics: true,
      child: InkWell(
        onTap: soldOut ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          curve: AppMotion.fastCurve,
          constraints: const BoxConstraints(minWidth: 72, minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(
            color: soldOut ? scheme.surfaceContainerHigh : selected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 2.5 : 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                variant.size,
                style: text.titleMedium!.copyWith(
                  color: soldOut ? scheme.onSurfaceVariant : selected ? scheme.onPrimaryContainer : scheme.onSurface,
                  decoration: soldOut ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(stockText, style: text.labelSmall!.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
