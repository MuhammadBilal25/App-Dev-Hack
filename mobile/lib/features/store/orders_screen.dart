import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

StatusKind orderStatusKind(String s) => switch (s) {
      'paid' || 'packed' || 'shipped' => StatusKind.info,
      'delivered' => StatusKind.success,
      'cancelled' || 'refunded' => StatusKind.neutral,
      _ => StatusKind.warning,
    };

IconData orderStatusIcon(String s) => switch (s) {
      'paid' => Icons.payments_outlined,
      'packed' => Icons.inventory_2_outlined,
      'shipped' => Icons.local_shipping_outlined,
      'delivered' => Icons.check_circle_outline,
      'cancelled' => Icons.cancel_outlined,
      'refunded' => Icons.undo,
      _ => Icons.hourglass_empty,
    };

/// Order history: the buyer's own orders, or (for club store staff) orders for their club.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key, this.managed = false});

  final bool managed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = managed ? 'managed' : 'mine';
    final value = ref.watch(ordersProvider(scope));
    return Scaffold(
      appBar: TenantAppBar(title: managed ? 'Club orders' : 'My orders'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: managed ? 'managed_orders_screen' : 'orders_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(ordersProvider(scope).future),
                children: [
                  AsyncView<List<Order>>(
                    id: 'orders',
                    value: value,
                    onRetry: () => ref.invalidate(ordersProvider(scope)),
                    builder: (orders) {
                      if (orders.isEmpty) {
                        return EmptyState(
                          id: 'orders_empty',
                          icon: Icons.receipt_long_outlined,
                          message: managed ? 'No orders for your club yet.' : 'No orders yet. Your purchases and receipts appear here.',
                          actionLabel: managed ? null : 'Go to the store',
                          onAction: managed ? null : () => context.go('/store'),
                        );
                      }
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < orders.length; i++) ...[
                              if (i > 0) const Divider(),
                              _OrderRow(order: orders[i], managed: managed),
                            ],
                          ],
                        ),
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

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.managed});

  final Order order;
  final bool managed;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final text = Theme.of(context).textTheme;
    final first = o.lines.isEmpty ? '' : o.lines.first.productName;
    final more = o.lines.length > 1 ? ' + ${o.lines.length - 1} more' : '';
    return Semantics(
      identifier: 'order_${o.id}',
      button: true,
      label: 'Order ${o.id}, $first$more, ${formatPrice(o.totalMinor)}, ${orderStatusLabel(o.status)}',
      excludeSemantics: true,
      child: ListTile(
        minTileHeight: 72,
        title: Text('$first$more', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${DateFormat('d MMM y, HH:mm').format(o.createdAt)}${managed ? ' · ${o.customerName}' : ''}\n${o.id}', maxLines: 2),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatPrice(o.totalMinor), style: text.titleSmall!.copyWith(fontFeatures: AppFonts.tabular)),
            const SizedBox(height: 4),
            StatusChip(kind: orderStatusKind(o.status), label: orderStatusLabel(o.status), icon: orderStatusIcon(o.status)),
          ],
        ),
        onTap: () => context.push('/orders/${Uri.encodeComponent(o.id)}${managed ? '?managed=1' : ''}'),
      ),
    );
  }
}

/// One order: lines, totals, payment and status timeline. Buyers can cancel before packing
/// (refunded at once); store staff move it to packed / shipped / delivered or refund it.
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.managed = false});

  final String orderId;
  final bool managed;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _busy = false;

  Future<void> _move(Order o, String to) async {
    final destructive = to == 'cancelled' || to == 'refunded';
    final r = await ConfirmSheet.show(
      context,
      id: 'confirm_order_$to',
      title: switch (to) {
        'cancelled' => 'Cancel this order?',
        'refunded' => 'Refund this order?',
        _ => 'Mark as ${orderStatusLabel(to).toLowerCase()}?',
      },
      message: destructive
          ? '${formatPrice(o.totalMinor)} goes back to the buyer\'s mock card and the items return to stock.'
          : 'The buyer sees the new status in their order history.',
      confirmLabel: switch (to) {
        'cancelled' => 'Cancel order',
        'refunded' => 'Refund',
        _ => 'Mark ${orderStatusLabel(to).toLowerCase()}',
      },
      variant: destructive ? AppButtonVariant.destructive : AppButtonVariant.primary,
      reasonLabel: destructive ? 'Reason' : null,
    );
    if (!r.confirmed || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).post('/api/v1/orders/${Uri.encodeComponent(o.id)}/status', body: {'status': to, if (r.reason.isNotEmpty) 'reason': r.reason});
      ref.invalidate(orderProvider(o.id));
      ref.invalidate(ordersProvider('mine'));
      ref.invalidate(ordersProvider('managed'));
      messenger.showSnackBar(SnackBar(content: Text('Order ${orderStatusLabel(to).toLowerCase()}.'), duration: AppMotion.snackbar));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(orderProvider(widget.orderId));
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: const TenantAppBar(title: 'Order'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'order_detail_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(orderProvider(widget.orderId).future),
                children: [
                  AsyncView<Order>(
                    id: 'order',
                    value: value,
                    onRetry: () => ref.invalidate(orderProvider(widget.orderId)),
                    builder: (o) {
                      final next = switch (o.status) {
                        'paid' => ['packed', 'cancelled'],
                        'packed' => ['shipped', 'refunded'],
                        'shipped' => ['delivered', 'refunded'],
                        'delivered' => ['refunded'],
                        _ => <String>[],
                      };
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(alignment: Alignment.centerLeft, child: StatusChip(kind: orderStatusKind(o.status), label: orderStatusLabel(o.status), icon: orderStatusIcon(o.status))),
                          const SizedBox(height: AppSpace.sm),
                          Semantics(header: true, child: Text('Order ${o.id}', style: text.titleLarge)),
                          Text(DateFormat('d MMM y, HH:mm').format(o.createdAt), style: text.bodyMedium!.copyWith(color: muted)),
                          if (widget.managed) Text('${o.customerName} · ${o.customerEmail}', style: text.bodyMedium!.copyWith(color: muted)),
                          const SectionLabel('Items'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpace.md),
                              child: Column(
                                children: [
                                  for (final l in o.lines)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                                      child: Row(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                            child: SizedBox.square(dimension: 48, child: ProductImageBox(imageUrl: l.imageUrl, category: 'apparel', iconSize: 28)),
                                          ),
                                          const SizedBox(width: AppSpace.md),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(l.productName, style: text.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                                                Text([if (l.label != 'Standard') l.label, '${l.quantity} × ${formatPrice(l.unitPriceMinor)}'].join(' · '), style: text.bodyMedium!.copyWith(color: muted)),
                                              ],
                                            ),
                                          ),
                                          Text(formatPrice(l.lineTotalMinor), style: text.bodyLarge!.copyWith(fontFeatures: AppFonts.tabular)),
                                        ],
                                      ),
                                    ),
                                  const Divider(),
                                  _kv(text, 'Subtotal', formatPrice(o.subtotalMinor)),
                                  if (o.discountMinor > 0) _kv(text, 'Discount${o.discountCode == null ? '' : ' (${o.discountCode})'}', '− ${formatPrice(o.discountMinor)}'),
                                  _kv(text, 'Total', formatPrice(o.totalMinor), bold: true),
                                  _kv(text, 'Payment', o.paymentStatus == 'refunded' ? 'Refunded${o.refundId == null ? '' : ' (${o.refundId})'}' : 'Captured'),
                                ],
                              ),
                            ),
                          ),
                          const SectionLabel('Status history'),
                          Card(
                            child: Column(
                              children: [
                                for (final h in o.history.reversed)
                                  ListTile(
                                    minTileHeight: 48,
                                    leading: Icon(orderStatusIcon(h.to)),
                                    title: Text(orderStatusLabel(h.to)),
                                    subtitle: Text([DateFormat('d MMM, HH:mm').format(h.at), if (h.reason != null) h.reason!].join(' · ')),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpace.xl),
                          AppButton(
                            id: 'order_receipt',
                            label: 'View receipt',
                            icon: Icons.receipt_long_outlined,
                            variant: AppButtonVariant.secondary,
                            onPressed: () => context.push('/receipt/${Uri.encodeComponent(o.id)}'),
                          ),
                          if (!widget.managed && o.status == 'paid') ...[
                            const SizedBox(height: AppSpace.md),
                            AppButton(id: 'order_cancel', label: 'Cancel order', variant: AppButtonVariant.destructive, loading: _busy, onPressed: () => _move(o, 'cancelled')),
                          ],
                          if (widget.managed)
                            for (final to in next) ...[
                              const SizedBox(height: AppSpace.md),
                              AppButton(
                                id: 'order_to_$to',
                                label: switch (to) {
                                  'cancelled' => 'Cancel and refund',
                                  'refunded' => 'Refund',
                                  _ => 'Mark ${orderStatusLabel(to).toLowerCase()}',
                                },
                                variant: to == 'cancelled' || to == 'refunded' ? AppButtonVariant.destructive : AppButtonVariant.primary,
                                loading: _busy,
                                onPressed: () => _move(o, to),
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

  Widget _kv(TextTheme text, String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(k, style: bold ? text.titleMedium : text.bodyMedium)),
            Text(v, style: (bold ? text.titleMedium!.copyWith(fontWeight: FontWeight.w800) : text.bodyMedium)!.copyWith(fontFeatures: AppFonts.tabular)),
          ],
        ),
      );
}
