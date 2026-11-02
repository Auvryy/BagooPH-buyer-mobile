import 'package:flutter/material.dart';

class CollectionPagination extends StatelessWidget {
  const CollectionPagination({
    super.key,
    required this.current,
    required this.last,
    required this.busy,
    required this.onPage,
  });

  final int current;
  final int last;
  final bool busy;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (last <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final iconOnly =
              constraints.maxWidth < 260 ||
              MediaQuery.textScalerOf(context).scale(14) >= 21;
          return Center(
            child: SizedBox(
              key: const ValueKey('collection-pagination-controls'),
              width: constraints.maxWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pageControl(
                    context,
                    previous: true,
                    compact: compact,
                    iconOnly: iconOnly,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Page $current of $last',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _pageControl(
                    context,
                    previous: false,
                    compact: compact,
                    iconOnly: iconOnly,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageControl(
    BuildContext context, {
    required bool previous,
    required bool compact,
    required bool iconOnly,
  }) {
    final label = previous ? 'Previous page' : 'Next page';
    final enabled = !busy && (previous ? current > 1 : current < last);
    final onPressed = enabled
        ? () => onPage(previous ? current - 1 : current + 1)
        : null;
    final icon = Icon(
      previous ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
    );

    if (iconOnly) {
      return IconButton.outlined(
        tooltip: label,
        onPressed: onPressed,
        icon: icon,
      );
    }

    return Tooltip(
      message: label,
      child: compact
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(previous ? 'Previous' : 'Next'),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: icon,
              label: Text(previous ? 'Previous' : 'Next'),
            ),
    );
  }
}
