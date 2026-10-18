import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/user.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/image_upload.dart';
import '../../core/widgets/remote_image.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../club/roster_manage_sheet.dart';
import '../fixtures/fixtures_screen.dart';

/// Club Manager workspace: squad size and position cover, transfer window, fixtures, store
/// summary (when store access is granted), low stock and the latest roster changes.
class ManagerDashboardScreen extends ConsumerWidget {
  const ManagerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(managerDashboardProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const TenantAppBar(title: 'My club'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'manager_dashboard',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(managerDashboardProvider.future),
                children: [
                  AsyncView<Cached<Map<String, dynamic>>>(
                    id: 'manager',
                    value: value,
                    onRetry: () => ref.invalidate(managerDashboardProvider),
                    builder: (r) {
                      final d = r.data;
                      final club = ClubCard.fromJson((d['club'] as Map).cast<String, dynamic>());
                      final squad = (d['squad'] as Map?)?.cast<String, dynamic>() ?? const {};
                      final positions = (squad['positions'] as List? ?? const []).whereType<Map>().toList();
                      final window = (squad['transfer_window'] as Map?)?.cast<String, dynamic>();
                      final store = (d['store'] as Map?)?.cast<String, dynamic>();
                      final low = (store?['low_stock'] as List? ?? const []).whereType<Map>().toList();
                      final changes = (d['roster_changes'] as List? ?? const []).whereType<Map<String, dynamic>>().map(RosterChange.fromJson).toList();
                      List<Fixture> fx(String k) => (d[k] as List? ?? const []).whereType<Map<String, dynamic>>().map(Fixture.fromJson).toList();
                      final upcoming = [...fx('live'), ...fx('upcoming')];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (r.fromCache) const CachedNotice(),
                          Row(
                            children: [
                              ClubBadge(name: club.name, logoUrl: club.logoUrl, size: 56),
                              const SizedBox(width: AppSpace.md),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Semantics(header: true, child: Text(club.name, style: text.titleLarge)),
                                  Text([club.leagueName, if (club.rank != null) '#${club.rank} · ${club.points} pts'].whereType<String>().join(' · '), style: text.bodyMedium),
                                ]),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.lg),
                          AppButton(
                            id: 'manager_roster',
                            label: 'Manage roster: add, transfer, loan, release',
                            icon: Icons.manage_accounts_outlined,
                            onPressed: () async {
                              final profile = await ref.read(clubProvider(club.id).future);
                              if (context.mounted) await showRosterManageSheet(context, profile.data);
                            },
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                            OutlinedButton.icon(onPressed: () => context.push('/club/${Uri.encodeComponent(club.id)}'), icon: const Icon(Icons.shield_outlined), label: const Text('Club profile')),
                            OutlinedButton.icon(onPressed: () => context.push('/club/${Uri.encodeComponent(club.id)}/edit'), icon: const Icon(Icons.edit_outlined), label: const Text('Edit profile')),
                            OutlinedButton.icon(onPressed: () => context.push('/club/${Uri.encodeComponent(club.id)}/history'), icon: const Icon(Icons.history), label: const Text('Roster history')),
                          ]),
                          const SectionLabel('Squad'),
                          StatGrid(tiles: [
                            StatTile(label: 'Players${squad['max'] == null ? '' : ' (max ${squad['max']})'}', value: '${squad['size'] ?? 0}', icon: Icons.groups_outlined),
                            StatTile(label: 'On loan here', value: '${squad['on_loan'] ?? 0}', icon: Icons.schedule_send_outlined),
                            StatTile(label: 'Transfer window', value: window == null ? '—' : 'Open', icon: Icons.swap_horiz),
                          ]),
                          if (window != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text('Transfers allowed ${window['open']} to ${window['close']}.', style: text.bodySmall!.copyWith(letterSpacing: 0))),
                          for (final p in positions)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpace.sm),
                              child: StatusChip(
                                kind: (p['have'] as num) >= (p['required'] as num) ? StatusKind.success : StatusKind.danger,
                                label: '${(p['position'] as String).toUpperCase()}: ${p['have']} of at least ${p['required']}',
                                icon: (p['have'] as num) >= (p['required'] as num) ? Icons.check : Icons.warning_amber_rounded,
                              ),
                            ),
                          const SectionLabel('Next matches'),
                          if (upcoming.isEmpty)
                            const EmptyState(id: 'manager_no_matches', icon: Icons.event_busy, message: 'No upcoming matches.')
                          else
                            Card(clipBehavior: Clip.antiAlias, child: Column(children: [for (final f in upcoming) FixtureRow(fixture: f, showLeague: true)])),
                          const SectionLabel('Club store'),
                          if (store == null)
                            const EmptyState(id: 'manager_no_store', icon: Icons.lock_outline, message: "Store management isn't enabled for your account. Ask the platform admin to grant store access.")
                          else ...[
                            StatGrid(tiles: [
                              StatTile(label: 'Products', value: '${store['products']}', icon: Icons.inventory_2_outlined),
                              StatTile(label: 'Open orders', value: '${store['open_orders']}', icon: Icons.local_shipping_outlined),
                              StatTile(label: 'Revenue', value: formatPrice((store['revenue_minor'] as num).toInt()), icon: Icons.payments_outlined),
                            ]),
                            const SizedBox(height: AppSpace.md),
                            Row(children: [
                              Expanded(child: AppButton(id: 'manager_products', label: 'Products', icon: Icons.inventory_2_outlined, variant: AppButtonVariant.secondary, onPressed: () => context.push('/manage/products'))),
                              const SizedBox(width: AppSpace.sm),
                              Expanded(child: AppButton(id: 'manager_orders', label: 'Orders', icon: Icons.receipt_long_outlined, variant: AppButtonVariant.secondary, onPressed: () => context.push('/manage/orders'))),
                            ]),
                            if (low.isNotEmpty) ...[
                              const SectionLabel('Low stock'),
                              Card(
                                child: Column(children: [
                                  for (final l in low)
                                    ListTile(
                                      leading: Icon(Icons.warning_amber_rounded, color: context.status.warning.fg),
                                      title: Text('${l['product_name']} (${l['label']})'),
                                      trailing: Text(l['stock'] == 0 ? 'Sold out' : '${l['stock']} left'),
                                      onTap: () => context.push('/manage/products/${Uri.encodeComponent(l['product_id'] as String)}'),
                                    ),
                                ]),
                              ),
                            ],
                          ],
                          const SectionLabel('Recent roster changes'),
                          if (changes.isEmpty)
                            const EmptyState(id: 'manager_no_changes', icon: Icons.history, message: 'No roster changes yet.')
                          else
                            Card(child: Column(children: [for (final c in changes) ListTile(title: Text('${c.playerName}: ${c.summary}'), subtitle: Text('by ${c.who}${c.why.isEmpty ? '' : ' · "${c.why}"'}'))])),
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

/// The products a store manager can edit (including hidden ones), with a New product button.
class ProductsManageScreen extends ConsumerWidget {
  const ProductsManageScreen({super.key});

  static final _query = FutureProvider.autoDispose<List<Product>>((ref) async {
    final user = ref.watch(currentUserProvider);
    final club = user?.role == UserRole.clubManager ? '&club_id=${user!.clubId}' : '';
    final body = await ref.read(apiClientProvider).get('/api/v1/products?include_inactive=1&sort=name$club') as Map<String, dynamic>;
    return Catalogue.fromJson(body).products;
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(_query);
    return Scaffold(
      appBar: const TenantAppBar(title: 'Products'),
      floatingActionButton: Semantics(
        identifier: 'products_new',
        button: true,
        child: FloatingActionButton.extended(
          onPressed: () async {
            await context.push('/manage/products/new');
            ref.invalidate(_query);
          },
          icon: const Icon(Icons.add),
          label: const Text('New product'),
        ),
      ),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'products_manage_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(_query.future),
                children: [
                  AsyncView<List<Product>>(
                    id: 'products_manage',
                    value: value,
                    onRetry: () => ref.invalidate(_query),
                    builder: (list) {
                      if (list.isEmpty) return const EmptyState(id: 'products_manage_empty', icon: Icons.inventory_2_outlined, message: 'No products yet. Tap New product to add your first shirt.');
                      return Column(children: [
                        for (final p in list)
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              minTileHeight: 72,
                              leading: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm), child: SizedBox.square(dimension: 52, child: ProductImageBox(imageUrl: p.imageUrl, category: p.category, iconSize: 28))),
                              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${p.clubName} · ${formatPrice(p.fromPriceMinor)} · ${p.variants.fold<int>(0, (n, v) => n + v.stock)} in stock'),
                              trailing: p.active ? (p.soldOut ? const StatusChip(kind: StatusKind.neutral, label: 'Sold out') : const Icon(Icons.chevron_right)) : const StatusChip(kind: StatusKind.neutral, label: 'Hidden', icon: Icons.visibility_off_outlined),
                              onTap: () async {
                                await context.push('/manage/products/${Uri.encodeComponent(p.id)}');
                                ref.invalidate(_query);
                              },
                            ),
                          ),
                        const SizedBox(height: 80),
                      ]);
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

class _VariantDraft {
  _VariantDraft({String size = '', String color = '', int stock = 0})
      : size = TextEditingController(text: size),
        color = TextEditingController(text: color),
        stock = TextEditingController(text: '$stock');

  final TextEditingController size;
  final TextEditingController color;
  final TextEditingController stock;

  void dispose() {
    size.dispose();
    color.dispose();
    stock.dispose();
  }
}

/// Create or edit a product: details, price and sale price, visibility, photos (upload with
/// preview and progress, choose the main photo, remove), and variants with stock per variant.
class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, this.productId});

  /// Null for a new product.
  final String? productId;

  @override
  ConsumerState<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _sale = TextEditingController();
  String? _category;
  String? _clubId;
  bool _active = true;
  final List<_VariantDraft> _drafts = [_VariantDraft(size: 'M', stock: 5)];
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  List<String> _bad = const [];

  bool get _isNew => widget.productId == null;

  @override
  void dispose() {
    for (final c in [_name, _desc, _price, _sale]) {
      c.dispose();
    }
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _load(Product p) {
    if (_loaded) return;
    _loaded = true;
    _name.text = p.name;
    _desc.text = p.description;
    _price.text = (p.listPriceMinor / 100).toStringAsFixed(0);
    final sale = p.variants.map((v) => v.salePriceMinor).whereType<int>().firstOrNull;
    _sale.text = sale == null ? '' : (sale / 100).toStringAsFixed(0);
    _category = p.category;
    _clubId = p.clubId;
    _active = p.active;
  }

  int? _minor(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', ''));
    return v == null ? null : (v * 100).round();
  }

  Future<void> _save() async {
    final price = _minor(_price);
    final sale = _sale.text.trim().isEmpty ? null : _minor(_sale);
    final bad = <String>[
      if (_name.text.trim().isEmpty) 'name',
      if (_category == null) 'category',
      if (price == null || price < 100) 'price_minor',
      if (_sale.text.trim().isNotEmpty && (sale == null || price == null || sale >= price)) 'sale_price_minor',
      if (_isNew && _clubId == null) 'club_id',
    ];
    if (bad.isNotEmpty) {
      setState(() => _bad = bad);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _bad = const [];
    });
    final api = ref.read(apiClientProvider);
    try {
      if (_isNew) {
        final variants = [
          for (final d in _drafts)
            {
              if (d.size.text.trim().isNotEmpty) 'size': d.size.text.trim(),
              if (d.color.text.trim().isNotEmpty) 'color': d.color.text.trim(),
              'stock': int.tryParse(d.stock.text.trim()) ?? 0,
            },
        ];
        final body = await api.post('/api/v1/products', body: {
          'club_id': _clubId,
          'name': _name.text.trim(),
          'description': _desc.text.trim(),
          'category': _category,
          'price_minor': price,
          'sale_price_minor': ?sale,
          'active': _active,
          'variants': variants,
        }) as Map<String, dynamic>;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product created. Add photos next.')));
        context.pushReplacement('/manage/products/${Uri.encodeComponent(body['product_id'] as String)}');
      } else {
        await api.patch('/api/v1/products/${Uri.encodeComponent(widget.productId!)}', body: {
          'name': _name.text.trim(),
          'description': _desc.text.trim(),
          'category': _category,
          'price_minor': price,
          'sale_price_minor': sale,
          'active': _active,
        });
        _invalidate();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product saved.'), duration: AppMotion.snackbar));
      }
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _bad = e.fields;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _invalidate() {
    if (widget.productId != null) ref.invalidate(productProvider(widget.productId!));
    ref.invalidate(catalogueProvider);
    ref.invalidate(homeProvider);
  }

  Future<void> _call(Future<void> Function() task, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await task();
      _invalidate();
      messenger.showSnackBar(SnackBar(content: Text(done), duration: AppMotion.snackbar));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editStock(Variant v) async {
    final c = TextEditingController(text: '${v.stock}');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stock for ${v.label}'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Units available')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    if (n == null || n < 0) return;
    await _call(() => ref.read(apiClientProvider).patch('/api/v1/variants/${Uri.encodeComponent(v.id)}', body: {'stock': n}), 'Stock updated: ${v.label} now $n.');
  }

  Future<void> _addVariant(String productId) async {
    final d = _VariantDraft(stock: 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add variant'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: d.size, decoration: const InputDecoration(labelText: 'Size (optional)', hintText: 'XS, S, M, L, XL, XXL')),
          TextField(controller: d.color, decoration: const InputDecoration(labelText: 'Colour (optional)')),
          TextField(controller: d.stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      await _call(
        () => ref.read(apiClientProvider).post('/api/v1/products/${Uri.encodeComponent(productId)}/variants', body: {
          if (d.size.text.trim().isNotEmpty) 'size': d.size.text.trim(),
          if (d.color.text.trim().isNotEmpty) 'color': d.color.text.trim(),
          'stock': int.tryParse(d.stock.text.trim()) ?? 0,
        }),
        'Variant added.',
      );
    }
    d.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (_isNew && _clubId == null && user?.role == UserRole.clubManager) _clubId = user!.clubId;
    final product = _isNew ? null : ref.watch(productProvider(widget.productId!));
    final categories = ref.watch(categoriesProvider).value ?? const <Facet>[];
    final clubs = user?.isSuperAdmin == true ? (ref.watch(clubsProvider).value?.data ?? const <ClubCard>[]) : const <ClubCard>[];
    final text = Theme.of(context).textTheme;
    final p = product?.value;
    if (p != null) _load(p);

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isNew && user?.isSuperAdmin == true) ...[
          DropdownButtonFormField<String>(
            initialValue: _clubId,
            decoration: InputDecoration(labelText: 'Club', errorText: _bad.contains('club_id') ? 'Choose the club that sells it.' : null),
            items: [for (final c in clubs) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _clubId = v),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        AppTextField(id: 'product_name', label: 'Product name', controller: _name, errorText: _bad.contains('name') ? 'Enter a name.' : null),
        const SizedBox(height: AppSpace.md),
        AppTextField(id: 'product_description', label: 'Description', controller: _desc),
        const SizedBox(height: AppSpace.md),
        Semantics(
          identifier: 'product_category',
          child: DropdownButtonFormField<String>(
            initialValue: categories.any((c) => c.id == _category) ? _category : null,
            decoration: InputDecoration(labelText: 'Category', errorText: _bad.contains('category') ? 'Choose a category.' : null),
            items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => _category = v),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Row(children: [
          Expanded(child: AppTextField(id: 'product_price', label: 'Price (PKR)', controller: _price, keyboardType: TextInputType.number, hint: '4500', errorText: _bad.contains('price_minor') ? 'At least PKR 1.' : null)),
          const SizedBox(width: AppSpace.md),
          Expanded(child: AppTextField(id: 'product_sale', label: 'Sale price (optional)', controller: _sale, keyboardType: TextInputType.number, hint: '3999', errorText: _bad.contains('sale_price_minor') ? 'Must be below the price.' : null)),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text('Prices are checked and totals calculated by the server; buyers always pay the server price.', style: text.bodySmall!.copyWith(letterSpacing: 0)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Visible in the store'),
          subtitle: const Text('Hidden products cannot be bought.'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
      ],
    );

    return Scaffold(
      appBar: TenantAppBar(title: _isNew ? 'New product' : 'Edit product'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'product_editor_screen',
              container: true,
              child: PageBody(
                children: [
                  if (!_isNew && p == null)
                    AsyncView<Product>(id: 'product_editor', value: product!, onRetry: () => ref.invalidate(productProvider(widget.productId!)), builder: (_) => const SizedBox.shrink())
                  else ...[
                    form,
                    if (_isNew) ...[
                      const SectionLabel('Variants and stock'),
                      Text('Add one row per size/colour. Leave size and colour empty for items without variants.', style: text.bodyMedium),
                      const SizedBox(height: AppSpace.sm),
                      for (var i = 0; i < _drafts.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.sm),
                          child: Row(children: [
                            Expanded(child: TextField(controller: _drafts[i].size, decoration: const InputDecoration(labelText: 'Size'))),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(child: TextField(controller: _drafts[i].color, decoration: const InputDecoration(labelText: 'Colour'))),
                            const SizedBox(width: AppSpace.sm),
                            SizedBox(width: 72, child: TextField(controller: _drafts[i].stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock'))),
                            IconButton(
                              tooltip: 'Remove variant',
                              onPressed: _drafts.length == 1 ? null : () => setState(() => _drafts.removeAt(i).dispose()),
                              icon: const Icon(Icons.close),
                            ),
                          ]),
                        ),
                      TextButton.icon(onPressed: () => setState(() => _drafts.add(_VariantDraft())), icon: const Icon(Icons.add), label: const Text('Add variant')),
                    ],
                    if (_bad.contains('variants')) const Padding(padding: EdgeInsets.only(top: AppSpace.sm), child: ErrorBanner(id: 'product_variants_error', message: 'Each size/colour combination must be different.')),
                    if (_error != null) ...[const SizedBox(height: AppSpace.lg), ErrorBanner(id: 'product_editor_error', message: _error!)],
                    const SizedBox(height: AppSpace.lg),
                    AppButton(id: 'product_save', label: _isNew ? 'Create product' : 'Save details', loading: _saving, onPressed: _save),
                    if (p != null) ...[
                      const SectionLabel('Photos'),
                      if (p.images.isEmpty)
                        Text('No photos yet. Fans see a placeholder until you add one.', style: text.bodyMedium)
                      else
                        Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.sm,
                          children: [
                            for (final img in p.images)
                              SizedBox(
                                width: 104,
                                child: Column(children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    child: SizedBox.square(dimension: 104, child: RemoteImage(path: img.url, fallback: ProductImageBox(imageUrl: null, category: p.category, iconSize: 40), semanticLabel: img.primary ? 'Main photo' : 'Photo')),
                                  ),
                                  if (img.primary)
                                    const Padding(padding: EdgeInsets.only(top: 4), child: StatusChip(kind: StatusKind.success, label: 'Main', icon: Icons.star))
                                  else
                                    TextButton(
                                      onPressed: () => _call(() => ref.read(apiClientProvider).patch('/api/v1/products/${Uri.encodeComponent(p.id)}/images/${Uri.encodeComponent(img.id)}'), 'Main photo changed.'),
                                      child: const Text('Make main'),
                                    ),
                                  TextButton(
                                    onPressed: () async {
                                      final r = await ConfirmSheet.show(context, id: 'confirm_remove_photo', title: 'Remove this photo?', message: 'It is deleted from storage.', confirmLabel: 'Remove', variant: AppButtonVariant.destructive);
                                      if (r.confirmed) await _call(() => ref.read(apiClientProvider).delete('/api/v1/products/${Uri.encodeComponent(p.id)}/images/${Uri.encodeComponent(img.id)}'), 'Photo removed.');
                                    },
                                    child: const Text('Remove'),
                                  ),
                                ]),
                              ),
                          ],
                        ),
                      const SizedBox(height: AppSpace.md),
                      ImageUploadPanel(
                        id: 'product_image_upload',
                        path: '/api/v1/products/${Uri.encodeComponent(p.id)}/images',
                        onUploaded: (_) {
                          _invalidate();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo uploaded.')));
                        },
                      ),
                      const SectionLabel('Variants and stock'),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          for (final v in p.variants)
                            ListTile(
                              minTileHeight: AppSize.rowMin,
                              title: Text(v.label),
                              subtitle: Text('${v.sku} · ${formatPrice(v.unitPriceMinor)}${v.active ? '' : ' · hidden'}'),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                StatusChip(kind: v.stock == 0 ? StatusKind.danger : v.stock <= 3 ? StatusKind.warning : StatusKind.success, label: '${v.stock}'),
                                PopupMenuButton<String>(
                                  tooltip: 'Variant actions',
                                  onSelected: (a) => a == 'stock'
                                      ? _editStock(v)
                                      : _call(() => ref.read(apiClientProvider).patch('/api/v1/variants/${Uri.encodeComponent(v.id)}', body: {'active': !v.active}), v.active ? 'Variant hidden.' : 'Variant visible.'),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'stock', child: Text('Set stock')),
                                    PopupMenuItem(value: 'toggle', child: Text(v.active ? 'Hide variant' : 'Show variant')),
                                  ],
                                ),
                              ]),
                              onTap: () => _editStock(v),
                            ),
                          ListTile(leading: const Icon(Icons.add), title: const Text('Add variant'), onTap: () => _addVariant(p.id)),
                        ]),
                      ),
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
