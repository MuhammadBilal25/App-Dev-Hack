import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';
import '../shell/tab_page.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabPage(
      id: 'store_screen',
      title: 'Store',
      children: [
        EmptyState(
          id: 'store_empty',
          icon: Icons.storefront_outlined,
          message: 'No products yet. Club merchandise appears here when a club adds it.',
        ),
      ],
    );
  }
}
