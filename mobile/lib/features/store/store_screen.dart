import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/user.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../shell/tab_page.dart';

const _sorts = {'newest': 'Newest', 'popular': 'Most popular', 'price_asc': 'Price: low to high', 'price_desc': 'Price: high to low'};

/// Store catalogue: search, category chips, filters (club, sport, size, colour, price, stock),
/// sort, and the product grid. Prices and stock are always live from the server.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  late final TextEditingController _search = TextEditingController(text: ref.read(catalogueQueryProvider)['q'] ?? '');
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => ref.read(catalogueQueryProvider.notifier).set('q', v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(catalogueProvider);
    final query = ref.watch(catalogueQueryProvider);
    final categories = ref.watch(categoriesProvider).value ?? const <Facet>[];
    final user = ref.watch(currentUserProvider);
    final filterCount = query.keys.where((k) => !['sort', 'q', 'category'].contains(k)).length;
    final canManage = user != null && (user.isSuperAdmin || (user.role == UserRole.clubManager && user.storeAccess));

    return TabPage(
      id: 'store_screen',
      title: 'Club Store',
      onRefresh: () => ref.refresh(catalogueProvider.future),
      trailing: canManage
          ? Semantics(
              identifier: 'store_manage',
              button: true,
              child: TextButton.icon(
                onPressed: () => context.push('/manage/products'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Manage'),
              ),
            )
          : null,
      children: [
        Semantics(
          identifier: 'store_search',
          label: 'Search the store',
          textField: true,
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search shirts, caps, clubs…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        ref.read(catalogueQueryProvider.notifier).set('q', null);
                        setState(() {});
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: AppSize.touch,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: query['category'] == null,
                  showCheckmark: false,
                  onSelected: (_) => ref.read(catalogueQueryProvider.notifier).set('category', null),
                ),
              ),
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.sm),
                  child: Semantics(
                    identifier: 'store_category_${c.id}',
                    child: ChoiceChip(
                      label: Text(c.name),
                      selected: query['category'] == c.id,
                      showCheckmark: false,
                      onSelected: (s) => ref.read(catalogueQueryProvider.notifier).set('category', s ? c.id : null),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            Semantics(
              identifier: 'store_filters',
              button: true,
              child: OutlinedButton.icon(
                onPressed: () => _showFilters(context, value.value),
                icon: const Icon(Icons.tune),
                label: Text(filterCount == 0 ? 'Filters' : 'Filters ($filterCount)'),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Semantics(
                identifier: 'store_sort',
                label: 'Sort products',
                child: DropdownButtonFormField<String>(
                  initialValue: query['sort'] ?? 'newest',
                  isExpanded: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.sort), contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.md)),
                  items: [for (final e in _sorts.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => ref.read(catalogueQueryProvider.notifier).set('sort', v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        AsyncView<Catalogue>(
          id: 'store',
          value: value,
          skeletonRows: 3,
          onRetry: () => ref.invalidate(catalogueProvider),
          builder: (cat) {
            if (cat.products.isEmpty) {
              final filtered = query.keys.any((k) => k != 'sort');
              return EmptyState(
                id: 'store_empty',
                icon: Icons.storefront_outlined,
                message: filtered ? 'No products match these filters.' : 'No products yet. Club merchandise appears here when a club adds it.',
                actionLabel: filtered ? 'Clear filters' : null,
                onAction: filtered
                    ? () {
                        _search.clear();
                        ref.read(catalogueQueryProvider.notifier).clearFilters();
                      }
                    : null,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text('${cat.products.length} ${cat.products.length == 1 ? 'product' : 'products'}', style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(height: AppSpace.sm),
                ProductGrid(products: cat.products),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _showFilters(BuildContext context, Catalogue? cat) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilterSheet(catalogue: cat),
    );
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({required this.catalogue});

  final Catalogue? catalogue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(catalogueQueryProvider);
    final n = ref.read(catalogueQueryProvider.notifier);
    final text = Theme.of(context).textTheme;
    final cat = catalogue;

    Widget chips(String title, String key, List<Facet> options) {
      if (options.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpace.lg),
          Text(title, style: text.titleSmall),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final o in options)
                FilterChip(
                  label: Text(o.name),
                  selected: q[key] == o.id,
                  onSelected: (s) => n.set(key, s ? o.id : null),
                ),
            ],
          ),
        ],
      );
    }

    const prices = {'': 'Any price', '200000': 'Up to PKR 2000', '400000': 'Up to PKR 4000'};
    return Semantics(
      identifier: 'store_filter_sheet',
      container: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Semantics(header: true, child: Text('Filters', style: text.titleLarge))),
                    TextButton(onPressed: n.clearFilters, child: const Text('Clear all')),
                  ],
                ),
                chips('Club', 'club_id', cat?.clubs ?? const []),
                chips('Sport', 'sport_id', cat?.sports ?? const []),
                chips('Size', 'size', [for (final s in cat?.sizes ?? const <String>[]) Facet(s, s)]),
                chips('Colour', 'color', [for (final c in cat?.colors ?? const <String>[]) Facet(c, c)]),
                const SizedBox(height: AppSpace.lg),
                Text('Price', style: text.titleSmall),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  children: [
                    for (final e in prices.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: (q['max_price'] ?? '') == e.key,
                        showCheckmark: false,
                        onSelected: (_) => n.set('max_price', e.key),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In stock only'),
                  value: q['in_stock'] == '1',
                  onChanged: (v) => n.set('in_stock', v ? '1' : null),
                ),
                const SizedBox(height: AppSpace.lg),
                AppButton(id: 'store_filter_done', label: 'Show products', onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
