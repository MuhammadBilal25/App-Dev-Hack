import 'package:flutter/material.dart';

import '../../core/layout/page_body.dart';
import '../../core/theme/tokens.dart';

/// Body of a tab root: screen title (Title L) then content, scrollable and width-capped.
class TabPage extends StatelessWidget {
  const TabPage({super.key, required this.id, required this.title, required this.children, this.onRefresh});

  final String id;
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: id,
      container: true,
      child: PageBody(
        onRefresh: onRefresh,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
          ),
          ...children,
        ],
      ),
    );
  }
}
