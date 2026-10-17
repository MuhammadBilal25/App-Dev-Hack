import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Full-width tabs with a brand underline on the selected one (Match detail, Club).
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({super.key, required this.id, required this.labels, required this.index, required this.onChanged});

  final String id;
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    identifier: '${id}_$i',
                    button: true,
                    selected: i == index,
                    label: labels[i],
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => onChanged(i),
                      child: AnimatedContainer(
                        duration: AppMotion.of(context, AppMotion.fast),
                        curve: AppMotion.fastCurve,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: i == index ? scheme.primary : Colors.transparent, width: 3)),
                        ),
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge!.copyWith(
                            color: i == index ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
