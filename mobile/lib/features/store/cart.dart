import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Checkout limits from the contract (Section 5.12): 1–10 lines, quantity 1..10 per variant.
const maxCartLines = 10;
const maxLineQuantity = 10;

class CartLine {
  const CartLine({required this.product, required this.variant, required this.quantity});

  final Product product;
  final Variant variant;
  final int quantity;

  int get totalMinor => variant.priceMinor * quantity;

  /// "Alpha Falcons Home Jersey (L)", used on the cart and the receipt.
  String get label => '${product.name} (${variant.size})';

  CartLine withQuantity(int q) => CartLine(product: product, variant: variant, quantity: q);
}

/// In-memory cart of the signed-in user. Each variant appears once; adding it again raises the
/// quantity, capped by its stock and the per-line limit.
class Cart extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() {
    ref.watch(currentUserProvider.select((u) => u?.id)); // a new user starts with an empty cart
    return const [];
  }

  int get count => state.fold(0, (n, l) => n + l.quantity);

  /// Highest quantity allowed for [v]: its stock, at most [maxLineQuantity].
  static int limitFor(Variant v) => min(v.stock, maxLineQuantity);

  /// Adds one of [v]. Returns false (and changes nothing) when no more can be added.
  bool add(Product p, Variant v) {
    final i = state.indexWhere((l) => l.variant.id == v.id);
    if (i >= 0) {
      if (state[i].quantity >= limitFor(v)) return false;
      state = [for (var j = 0; j < state.length; j++) j == i ? state[j].withQuantity(state[j].quantity + 1) : state[j]];
      return true;
    }
    if (state.length >= maxCartLines || limitFor(v) < 1) return false;
    state = [...state, CartLine(product: p, variant: v, quantity: 1)];
    return true;
  }

  void setQuantity(String variantId, int q) {
    state = [
      for (final l in state)
        if (l.variant.id != variantId)
          l
        else if (q > 0)
          l.withQuantity(min(q, limitFor(l.variant)))
    ];
  }

  void remove(String variantId) => setQuantity(variantId, 0);

  void clear() => state = const [];
}

final cartProvider = NotifierProvider<Cart, List<CartLine>>(Cart.new);

String _orderId() {
  final r = Random.secure();
  return 'ord-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join()}';
}

/// One mock-card checkout of [lines] (Section 5.12). Returns the paid order; throws ApiException
/// with a plain-language message on failure. Refreshes the catalogue's stock either way it matters.
Future<Map<String, dynamic>> checkoutLines(WidgetRef ref, List<CartLine> lines, {String? discountCode}) async {
  final user = ref.read(currentUserProvider);
  final code = discountCode?.trim().toUpperCase() ?? '';
  final Map<String, dynamic> body;
  try {
    body = await ref.read(apiClientProvider).post('/audit/v1/checkout', body: {
      'order_id': _orderId(),
      'customer_id': user?.id ?? 'guest',
      'items': [
        for (final l in lines) {'variant_id': l.variant.id, 'quantity': l.quantity},
      ],
      if (code.isNotEmpty) 'discount_code': code,
      'payment': {'token': 'tok_success'},
    }) as Map<String, dynamic>;
  } on ApiException catch (e) {
    if (e.code == 'OUT_OF_STOCK') ref.invalidate(catalogueProvider); // show the real stock again
    rethrow;
  }
  ref.invalidate(catalogueProvider);
  return body;
}

/// Receipt route payload: the paid order plus readable names for its variant ids.
Map<String, Object> receiptExtra(Map<String, dynamic> order, List<CartLine> lines) => {
      'order': order,
      'names': {for (final l in lines) l.variant.id: l.label},
    };
