import 'package:flutter/material.dart';

import '../../core/layout/page_body.dart';
import '../../core/theme/tokens.dart';

/// Body of a tab root: screen title (Title L) then content, scrollable and width-capped.
class TabPage extends StatelessWidget {
  const TabPage({super.key, required this.id, required this.title, required this.children, this.onRefresh, this.subtitle, this.trailing});

  final String id;
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: id,
      container: true,
      child: PageBody(
        onRefresh: onRefresh,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
                      if (subtitle != null)
                        Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
