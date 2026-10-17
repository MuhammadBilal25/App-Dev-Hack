import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Scrollable screen body, centred and capped at 600 dp so landscape keeps the same layout
/// (UI.md §10). Every screen scrolls; nothing uses fixed heights.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh, this.padding});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding ?? const EdgeInsets.all(AppSpace.lg),
      children: [
        for (final c in children)
          Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth), child: c),
          ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// Section label: Caption style, UPPERCASE (UI.md §4).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.sm),
      child: Semantics(header: true, child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.bodySmall)),
    );
  }
}
