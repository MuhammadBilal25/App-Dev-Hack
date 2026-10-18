import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cart/cart.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/remote_image.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Product page: photos, price (with sale), size and colour pickers that resolve to a variant,
/// live stock, quantity, Add to cart and Buy now.
class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  String? _size;
  String? _color;
  int _qty = 1;
  int _photo = 0;
  bool _initialised = false;

  void _init(Product p) {
    if (_initialised) return;
    _initialised = true;
    final first = p.sellable.where((v) => v.stock > 0).firstOrNull ?? p.sellable.firstOrNull;
    _size = first?.size;
    _color = first?.color;
  }

  Variant? _variant(Product p) => p.sellable.where((v) => v.size == _size && v.color == _color).firstOrNull;

  Future<void> _add(Product p, {required bool buyNow}) async {
    final v = _variant(p);
    if (v == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(cartProvider.notifier).add(p, v, quantity: _qty);
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Your cart is full for this item (max 10 each, 10 different items).')));
      return;
    }
    if (buyNow) {
      context.push('/cart');
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('Added to cart: ${p.name}${v.label == 'Standard' ? '' : ' (${v.label})'} × $_qty'),
        duration: AppMotion.snackbar,
        action: SnackBarAction(label: 'View cart', onPressed: () => context.push('/cart')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(productProvider(widget.productId));
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: TenantAppBar(title: value.value?.name ?? 'Product'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'product_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(productProvider(widget.productId).future),
                children: [
                  AsyncView<Product>(
                    id: 'product',
                    value: value,
                    onRetry: () => ref.invalidate(productProvider(widget.productId)),
                    builder: (p) {
                      _init(p);
                      final v = _variant(p);
                      final sizes = p.sellable.map((x) => x.size).whereType<String>().toSet().toList();
                      final colors = p.sellable.map((x) => x.color).whereType<String>().toSet().toList();
                      final maxQty = v == null ? 1 : v.stock.clamp(1, Cart.maxQuantity);
                      if (_qty > maxQty) _qty = maxQty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Gallery(product: p, index: _photo, onChanged: (i) => setState(() => _photo = i)),
                          const SizedBox(height: AppSpace.lg),
                          if (!p.active) ...[
                            const Align(alignment: Alignment.centerLeft, child: StatusChip(kind: StatusKind.neutral, label: 'Hidden from fans', icon: Icons.visibility_off_outlined)),
                            const SizedBox(height: AppSpace.sm),
                          ],
                          Semantics(header: true, child: Text(p.name, style: text.headlineSmall)),
                          const SizedBox(height: AppSpace.xs),
                          InkWell(
                            onTap: p.clubId.isEmpty ? null : () => context.push('/club/${Uri.encodeComponent(p.clubId)}'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                              child: Text('${p.clubName}${p.sportName == null ? '' : ' · ${p.sportName}'} · ${p.categoryName}', style: text.bodyMedium!.copyWith(color: muted)),
                            ),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          PriceText(
                            priceMinor: v?.unitPriceMinor ?? p.fromPriceMinor,
                            listPriceMinor: v?.priceMinor ?? p.listPriceMinor,
                            style: text.headlineSmall,
                          ),
                          if (sizes.isNotEmpty) ...[
                            const SectionLabel('Size'),
                            Wrap(
                              spacing: AppSpace.sm,
                              runSpacing: AppSpace.sm,
                              children: [
                                for (final s in sizes)
                                  _OptionChip(
                                    id: 'size_${s.toLowerCase()}',
                                    label: s,
                                    selected: _size == s,
                                    soldOut: !p.sellable.any((x) => x.size == s && (_color == null || x.color == _color) && x.stock > 0),
                                    onTap: () => setState(() {
                                      _size = s;
                                      if (!p.sellable.any((x) => x.size == s && x.color == _color)) _color = p.sellable.firstWhere((x) => x.size == s).color;
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          if (colors.isNotEmpty) ...[
                            const SectionLabel('Colour'),
                            Wrap(
                              spacing: AppSpace.sm,
                              runSpacing: AppSpace.sm,
                              children: [
                                for (final c in colors)
                                  _OptionChip(
                                    id: 'color_${c.toLowerCase()}',
                                    label: c,
                                    selected: _color == c,
                                    soldOut: !p.sellable.any((x) => x.color == c && (_size == null || x.size == _size) && x.stock > 0),
                                    onTap: () => setState(() {
                                      _color = c;
                                      if (!p.sellable.any((x) => x.color == c && x.size == _size)) _size = p.sellable.firstWhere((x) => x.color == c).size;
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpace.lg),
                          _StockLine(variant: v),
                          if (v != null && v.stock > 0) ...[
                            const SizedBox(height: AppSpace.md),
                            Row(
                              children: [
                                Text('Quantity', style: text.titleSmall),
                                const Spacer(),
                                QuantityStepper(
                                  id: 'product_qty',
                                  value: _qty,
                                  max: maxQty,
                                  onChanged: (q) => setState(() => _qty = q),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpace.xl),
                          AppButton(
                            id: 'product_buy_now',
                            label: v == null || v.stock <= 0 ? 'Sold out · pick another option' : 'Buy now · ${formatPrice(v.unitPriceMinor * _qty)}',
                            variant: AppButtonVariant.cta,
                            icon: Icons.flash_on_outlined,
                            onPressed: v == null || v.stock <= 0 || !p.active ? null : () => _add(p, buyNow: true),
                          ),
                          const SizedBox(height: AppSpace.md),
                          AppButton(
                            id: 'product_add_to_cart',
                            label: 'Add to cart',
                            variant: AppButtonVariant.secondary,
                            icon: Icons.add_shopping_cart,
                            onPressed: v == null || v.stock <= 0 || !p.active ? null : () => _add(p, buyNow: false),
                          ),
                          if (p.description.isNotEmpty) ...[
                            const SectionLabel('About this item'),
                            Text(p.description, style: text.bodyLarge),
                          ],
                          if (v != null) ...[
                            const SizedBox(height: AppSpace.md),
                            Text('SKU ${v.sku}', style: text.bodySmall!.copyWith(color: muted, letterSpacing: 0)),
                          ],
                          if (p.canManage) ...[
                            const SizedBox(height: AppSpace.xl),
                            AppButton(
                              id: 'product_edit',
                              label: 'Edit product, photos and stock',
                              icon: Icons.edit_outlined,
                              variant: AppButtonVariant.text,
                              onPressed: () => context.push('/manage/products/${Uri.encodeComponent(p.id)}'),
                            ),
                          ],
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

class _Gallery extends StatelessWidget {
  const _Gallery({required this.product, required this.index, required this.onChanged});

  final Product product;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final scheme = Theme.of(context).colorScheme;
    final images = p.images.isEmpty ? <ProductImage>[] : ([...p.images]..sort((a, b) => (b.primary ? 1 : 0) - (a.primary ? 1 : 0)));
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 1.2,
            child: images.isEmpty
                ? ProductImageBox(imageUrl: null, category: p.category, iconSize: 96)
                : PageView.builder(
                    itemCount: images.length,
                    onPageChanged: onChanged,
                    itemBuilder: (_, i) => RemoteImage(
                      path: images[i].url,
                      semanticLabel: 'Photo ${i + 1} of ${images.length}: ${p.name}',
                      fallback: ProductImageBox(imageUrl: null, category: p.category, iconSize: 96),
                    ),
                  ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: AppSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < images.length; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i == index ? scheme.primary : scheme.outlineVariant),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.id, required this.label, required this.selected, required this.soldOut, required this.onTap});

  final String id;
  final String label;
  final bool selected;
  final bool soldOut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: id,
      button: true,
      selected: selected,
      label: '$label${soldOut ? ', sold out' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          constraints: const BoxConstraints(minWidth: 56, minHeight: AppSize.touch),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 2.5 : 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: text.titleMedium!.copyWith(
                  color: soldOut ? scheme.onSurfaceVariant : selected ? scheme.primary : scheme.onSurface,
                  decoration: soldOut ? TextDecoration.lineThrough : null,
                ),
              ),
              if (selected) ...[const SizedBox(width: 4), Icon(Icons.check, size: 18, color: scheme.primary)],
            ],
          ),
        ),
      ),
    );
  }
}

class _StockLine extends StatelessWidget {
  const _StockLine({required this.variant});

  final Variant? variant;

  @override
  Widget build(BuildContext context) {
    final v = variant;
    if (v == null) return const StatusChip(kind: StatusKind.neutral, label: 'This combination is not sold', icon: Icons.block);
    if (v.stock <= 0) return const Align(alignment: Alignment.centerLeft, child: StatusChip(kind: StatusKind.neutral, label: 'Sold out', icon: Icons.block));
    if (v.stock == 1) {
      return const Align(alignment: Alignment.centerLeft, child: StatusChip(kind: StatusKind.warning, label: 'Last one!', icon: Icons.local_fire_department_outlined));
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusChip(kind: v.stock <= 3 ? StatusKind.warning : StatusKind.success, label: '${v.stock} in stock', icon: Icons.check_circle_outline),
    );
  }
}

/// − value + with 48 dp buttons; [max] caps it.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.id, required this.value, required this.onChanged, this.max = 10, this.min = 1});

  final String id;
  final int value;
  final int max;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: id,
      label: 'Quantity $value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            tooltip: 'Decrease quantity',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.center, style: text.titleMedium)),
          IconButton.outlined(
            tooltip: 'Increase quantity',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
