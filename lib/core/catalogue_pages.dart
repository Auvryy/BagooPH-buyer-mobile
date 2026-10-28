import 'package:flutter/material.dart';

class CataloguePages extends StatelessWidget {
  const CataloguePages({
    super.key,
    required this.current,
    required this.last,
    required this.total,
    required this.onPage,
    this.from,
    this.to,
    this.busy = false,
  });
  final int current, last, total;
  final int? from, to;
  final bool busy;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 12,
    children: [
      Text(
        from != null && to != null
            ? '$from–$to of $total products'
            : '$total products · Page $current of $last',
      ),
      IconButton(
        tooltip: 'Previous page',
        onPressed: busy || current <= 1 ? null : () => onPage(current - 1),
        icon: const Icon(Icons.chevron_left),
      ),
      SizedBox(
        width: 100,
        child: TextFormField(
          key: ValueKey('catalogue-page-$current'),
          initialValue: '$current',
          enabled: !busy && last > 1,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.go,
          decoration: const InputDecoration(labelText: 'Go to page'),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            final number = int.tryParse(value ?? '');
            return number == null || number < 1 || number > last
                ? '1–$last'
                : null;
          },
          onFieldSubmitted: (value) {
            final number = int.tryParse(value);
            if (number != null &&
                number >= 1 &&
                number <= last &&
                number != current) {
              onPage(number);
            }
          },
        ),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: busy || current >= last ? null : () => onPage(current + 1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}
