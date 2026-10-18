import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../brand/club_crest.dart';
import '../brand/jersey_icon.dart';
import '../theme/status_colors.dart';
import '../theme/tenant.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'remote_image.dart';
import 'status_chip.dart';

/// Icon for a sport's `icon` key (from the sport config metadata); unknown keys get a trophy.
IconData sportIcon(String key) => switch (key) {
      'soccer' || 'football' => Icons.sports_soccer,
      'basketball' => Icons.sports_basketball,
      'cricket' => Icons.sports_cricket,
      'esports' => Icons.sports_esports,
      'hockey' => Icons.sports_hockey,
      'volleyball' => Icons.sports_volleyball,
      'tennis' || 'badminton' || 'table_tennis' => Icons.sports_tennis,
      'rugby' => Icons.sports_rugby,
      'baseball' => Icons.sports_baseball,
      'handball' || 'netball' => Icons.sports_handball,
      'kabaddi' => Icons.sports_kabaddi,
      'golf' => Icons.sports_golf,
      _ => Icons.emoji_events_outlined,
    };

/// Club logo when one was uploaded, otherwise the generated crest (also the offline fallback).
class ClubBadge extends StatelessWidget {
  const ClubBadge({super.key, required this.name, this.logoUrl, this.size = 32, this.decorative = true});

  final String name;
  final String? logoUrl;
  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final crest = ClubCrest(name: name, size: size, decorative: true);
    final child = logoUrl == null
        ? crest
        : ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.2),
            child: SizedBox(width: size, height: size * 1.15, child: RemoteImage(path: logoUrl, fallback: crest, fit: BoxFit.contain)),
          );
    if (decorative) return ExcludeSemantics(child: child);
    return Semantics(label: '$name crest', image: true, excludeSemantics: true, child: child);
  }
}

/// Section title with an optional "See all" action (48 dp tap target).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel = 'See all', this.onAction, this.id});

  final String title;
  final String actionLabel;
  final VoidCallback? onAction;
  final String? id;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.xs),
      child: Row(
        children: [
          Expanded(child: Semantics(header: true, child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.bodySmall))),
          if (onAction != null)
            Semantics(
              identifier: id,
              button: true,
              label: '$actionLabel: $title',
              excludeSemantics: true,
              child: TextButton(onPressed: onAction, child: Text(actionLabel)),
            ),
        ],
      ),
    );
  }
}

/// Small note on seeded demo records, so sample content is never presented as real.
class DemoNote extends StatelessWidget {
  const DemoNote({super.key, this.text = 'Demo data'});

  final String text;

  @override
  Widget build(BuildContext context) => StatusChip(kind: StatusKind.info, label: text, icon: Icons.science_outlined);
}

/// A horizontally scrolling row of cards. Cards keep their natural height (no fixed box), so
/// large text never overflows.
class HorizontalCards extends StatelessWidget {
  const HorizontalCards({super.key, this.height, required this.children});

  /// Unused; kept for call sites that state a typical height.
  final double? height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.md),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Product photo (primary image) with the jersey / bag icon as fallback.
class ProductImageBox extends StatelessWidget {
  const ProductImageBox({super.key, required this.imageUrl, required this.category, this.iconSize = 56});

  final String? imageUrl;
  final String category;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: category == 'apparel' || category == 'training' || category == 'sportswear'
          ? JerseyIcon(size: iconSize, color: scheme.primary)
          : Icon(category == 'caps' ? Icons.face_retouching_natural : category == 'bags' ? Icons.work_outline : category == 'digital' ? Icons.play_circle_outline : Icons.shopping_bag_outlined,
              size: iconSize * 0.85, color: scheme.primary),
    );
    return RemoteImage(path: imageUrl, fallback: fallback);
  }
}

/// Price with the list price struck through when on sale.
class PriceText extends StatelessWidget {
  const PriceText({super.key, required this.priceMinor, this.listPriceMinor, this.prefix = '', this.style});

  final int priceMinor;
  final int? listPriceMinor;
  final String prefix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final base = (style ?? text.bodyMedium!).copyWith(fontFeatures: AppFonts.tabular);
    final sale = listPriceMinor != null && listPriceMinor! > priceMinor;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$prefix${formatPrice(priceMinor)}', style: base.copyWith(fontWeight: FontWeight.w700)),
        if (sale) ...[
          const TextSpan(text: '  '),
          TextSpan(
            text: formatPrice(listPriceMinor!),
            style: base.copyWith(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: (base.fontSize ?? 14) * 0.85),
          ),
        ],
      ]),
      semanticsLabel: sale ? 'On sale, ${formatPrice(priceMinor)}, was ${formatPrice(listPriceMinor!)}' : formatPrice(priceMinor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Product card used by the store grid and the home screen. Opens the product page.
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, this.width});

  final Product product;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = product;
    final card = Semantics(
      identifier: 'product_${p.id}',
      button: true,
      label: '${p.name}, ${p.clubName}, from ${formatPrice(p.fromPriceMinor)}${p.onSale ? ', on sale' : ''}${p.soldOut ? ', sold out' : ''}',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/product/${Uri.encodeComponent(p.id)}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductImageBox(imageUrl: p.imageUrl, category: p.category),
                    if (p.onSale && !p.soldOut)
                      const Positioned(left: AppSpace.sm, top: AppSpace.sm, child: StatusChip(kind: StatusKind.success, label: 'Sale', icon: Icons.sell_outlined)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(p.clubName, style: text.bodySmall!.copyWith(color: muted, letterSpacing: 0), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    PriceText(priceMinor: p.fromPriceMinor, listPriceMinor: p.listPriceMinor),
                    if (p.soldOut || p.lowStock) ...[
                      const SizedBox(height: AppSpace.sm),
                      p.soldOut
                          ? const StatusChip(kind: StatusKind.neutral, label: 'Sold out', icon: Icons.block)
                          : const StatusChip(kind: StatusKind.warning, label: 'Low stock', icon: Icons.local_fire_department_outlined),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// Grid of product tiles: two columns on phones, three on wide screens.
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 520 ? 3 : 2;
        final w = (c.maxWidth - AppSpace.md * (cols - 1)) / cols;
        return Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.md,
          children: [for (final p in products) SizedBox(width: w, child: ProductTile(product: p))],
        );
      },
    );
  }
}

/// Compact club card (crest, name, league) that opens the club profile.
class ClubTile extends StatelessWidget {
  const ClubTile({super.key, required this.club, this.width = 150});

  final ClubCard club;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: width,
      child: Semantics(
        identifier: 'club_${club.id}',
        button: true,
        label: '${club.name}${club.leagueName == null ? '' : ', ${club.leagueName}'}${club.rank == null ? '' : ', position ${club.rank}'}',
        excludeSemantics: true,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/club/${Uri.encodeComponent(club.id)}'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClubBadge(name: club.name, logoUrl: club.logoUrl, size: 36),
                  const SizedBox(height: AppSpace.sm),
                  Text(club.name, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (club.sportName != null) Text(club.sportName!, style: text.bodySmall!.copyWith(color: muted, letterSpacing: 0), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (club.rank != null) Text('#${club.rank} · ${club.points} pts', style: text.bodySmall!.copyWith(color: muted, letterSpacing: 0)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// List row for a league: sport icon, name, season and format.
class LeagueTile extends StatelessWidget {
  const LeagueTile({super.key, required this.league, this.onTap, this.trailing});

  final League league;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final l = league;
    final sub = [l.sportName, if (l.season.isNotEmpty) 'Season ${l.season}', formatLabel(l.format)].join(' · ');
    return Semantics(
      identifier: 'league_${l.id}',
      button: true,
      label: '${l.name}, $sub${l.liveCount > 0 ? ', ${l.liveCount} live' : ''}',
      excludeSemantics: true,
      child: ListTile(
        minTileHeight: AppSize.rowMin,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(sportIcon(l.sportId), color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
        trailing: trailing ?? (l.liveCount > 0 ? StatusChip(kind: StatusKind.danger, label: '${l.liveCount} live', icon: Icons.circle) : const Icon(Icons.chevron_right)),
        onTap: onTap ?? () => context.push('/leagues/${Uri.encodeComponent(l.id)}'),
      ),
    );
  }
}

/// A small labelled number (dashboards, club and player stats).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: scheme.outlineVariant)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) Icon(icon, size: 20, color: scheme.primary),
            Text(value, style: text.headlineSmall!.copyWith(fontFeatures: AppFonts.tabular), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(label, style: text.bodySmall!.copyWith(letterSpacing: 0, color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Lays stat tiles out in rows of [perRow].
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles, this.perRow = 3});

  final List<Widget> tiles;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = c.maxWidth < 340 ? 2 : perRow;
      final w = (c.maxWidth - AppSpace.sm * (n - 1)) / n;
      return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

/// Initials avatar for people (staff, users).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundColor: scheme.onSurface,
      child: Text(initialsOf(name, max: 2), style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
