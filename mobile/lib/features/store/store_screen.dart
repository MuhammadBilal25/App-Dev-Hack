import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand/jersey_icon.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../shell/tab_page.dart';
import 'product_sheet.dart';

class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(catalogueProvider);
    return TabPage(
      id: 'store_screen',
      title: 'Club Store',
      onRefresh: () => ref.refresh(catalogueProvider.future),
      children: [
        AsyncView<List<Product>>(
          id: 'store',
          value: value,
          skeletonRows: 3,
          onRetry: () => ref.invalidate(catalogueProvider),
          builder: (products) {
            if (products.isEmpty) {
              return const EmptyState(
                id: 'store_empty',
                icon: Icons.storefront_outlined,
                message: 'No products yet. Club merchandise appears here when a club adds it.',
              );
            }
            return LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - AppSpace.md) / 2;
                return Wrap(
                  spacing: AppSpace.md,
                  runSpacing: AppSpace.md,
                  children: [for (final p in products) SizedBox(width: w, child: ProductCard(product: p))],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final p = product;
    final lowStock = p.variants.any((v) => v.stock == 1);
    return Semantics(
      identifier: 'product_${p.id}',
      button: true,
      label: '${p.name}, from ${formatPrice(p.fromPriceMinor)}${p.soldOut ? ', sold out' : ''}',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showProductSheet(context, p),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: scheme.primaryContainer,
                  alignment: Alignment.center,
                  child: p.category == 'apparel'
                      ? JerseyIcon(size: 64, color: scheme.primary)
                      : Icon(Icons.shopping_bag_outlined, size: 56, color: scheme.primary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(formatPrice(p.fromPriceMinor), style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant, fontFeatures: AppFonts.tabular)),
                    if (p.soldOut || lowStock) ...[
                      const SizedBox(height: AppSpace.sm),
                      p.soldOut
                          ? const StatusChip(kind: StatusKind.neutral, label: 'Sold out', icon: Icons.block)
                          : const StatusChip(kind: StatusKind.warning, label: 'Last one!', icon: Icons.local_fire_department_outlined),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
