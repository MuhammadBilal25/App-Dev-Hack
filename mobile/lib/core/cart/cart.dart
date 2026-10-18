import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../data/models.dart';

/// Overridden in `main()` with the box opened before `runApp`.
final cartBoxProvider = Provider<Box<String>>((ref) => throw UnimplementedError('cartBoxProvider not overridden'));

const cartBoxName = 'cart';

/// One cart line as stored on the phone. The price is what the buyer saw when adding it; the
/// server re-prices every line at checkout and the cart shows any change.
class CartItem {
  const CartItem({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.label,
    required this.clubName,
    required this.unitPriceMinor,
    required this.quantity,
    this.imageUrl,
  });

  final String variantId;
  final String productId;
  final String productName;
  final String label;
  final String clubName;
  final String? imageUrl;
  final int unitPriceMinor;
  final int quantity;

  CartItem withQuantity(int q) => copy(quantity: q);

  CartItem copy({int? quantity, int? unitPriceMinor}) => CartItem(
        variantId: variantId,
        productId: productId,
        productName: productName,
        label: label,
        clubName: clubName,
        imageUrl: imageUrl,
        unitPriceMinor: unitPriceMinor ?? this.unitPriceMinor,
        quantity: quantity ?? this.quantity,
      );

  Map<String, dynamic> toJson() => {
        'variant_id': variantId,
        'product_id': productId,
        'product_name': productName,
        'label': label,
        'club_name': clubName,
        'image_url': imageUrl,
        'unit_price_minor': unitPriceMinor,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        variantId: j['variant_id'] as String,
        productId: j['product_id'] as String,
        productName: (j['product_name'] as String?) ?? '',
        label: (j['label'] as String?) ?? '',
        clubName: (j['club_name'] as String?) ?? '',
        imageUrl: j['image_url'] as String?,
        unitPriceMinor: (j['unit_price_minor'] as num).toInt(),
        quantity: (j['quantity'] as num).toInt(),
      );
}

/// The shopping cart, persisted in Hive so it survives restarts. Max 10 of one variant and
/// 10 lines (the checkout limits).
class Cart extends Notifier<List<CartItem>> {
  static const maxQuantity = 10;
  static const maxLines = 10;

  Box<String> get _box => ref.read(cartBoxProvider);

  @override
  List<CartItem> build() {
    final box = ref.watch(cartBoxProvider);
    return box.values.map((s) => CartItem.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
  }

  int get count => state.fold(0, (n, i) => n + i.quantity);

  /// Adds [quantity] of a variant. Returns false when the cart is full or the line would exceed
  /// the per-item limit.
  Future<bool> add(Product p, Variant v, {int quantity = 1}) async {
    final existing = state.where((i) => i.variantId == v.id).firstOrNull;
    if (existing == null && state.length >= maxLines) return false;
    final q = (existing?.quantity ?? 0) + quantity;
    if (q > maxQuantity) return false;
    final item = CartItem(
      variantId: v.id,
      productId: p.id,
      productName: p.name,
      label: v.label,
      clubName: p.clubName,
      imageUrl: p.imageUrl,
      unitPriceMinor: v.unitPriceMinor,
      quantity: q,
    );
    await _box.put(v.id, jsonEncode(item.toJson()));
    state = existing == null ? [...state, item] : [for (final i in state) i.variantId == v.id ? item : i];
    return true;
  }

  Future<void> setQuantity(String variantId, int quantity) async {
    if (quantity <= 0) return remove(variantId);
    final q = quantity.clamp(1, maxQuantity);
    final next = [for (final i in state) i.variantId == variantId ? i.withQuantity(q) : i];
    final item = next.firstWhere((i) => i.variantId == variantId);
    await _box.put(variantId, jsonEncode(item.toJson()));
    state = next;
  }

  /// Records the price the buyer accepted after the server reported a change.
  Future<void> acceptPrice(String variantId, int unitPriceMinor) async {
    final next = [for (final i in state) i.variantId == variantId ? i.copy(unitPriceMinor: unitPriceMinor) : i];
    final item = next.firstWhere((i) => i.variantId == variantId);
    await _box.put(variantId, jsonEncode(item.toJson()));
    state = next;
  }

  Future<void> remove(String variantId) async {
    await _box.delete(variantId);
    state = state.where((i) => i.variantId != variantId).toList();
  }

  Future<void> clear() async {
    await _box.clear();
    state = const [];
  }
}

final cartProvider = NotifierProvider<Cart, List<CartItem>>(Cart.new);

final cartCountProvider = Provider<int>((ref) => ref.watch(cartProvider).fold(0, (n, i) => n + i.quantity));
