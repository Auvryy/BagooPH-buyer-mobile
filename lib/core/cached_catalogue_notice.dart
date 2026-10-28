import 'package:flutter/material.dart';

import 'widgets.dart';

class CachedCatalogueNotice extends StatelessWidget {
  const CachedCatalogueNotice({
    super.key,
    required this.savedAt,
    required this.onRefresh,
  });
  final DateTime savedAt;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final date = savedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final recorded =
        '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Notice(
          'Saved browsing data · $recorded\nPrices and availability may have changed. Connect and refresh before shopping. Some photos may need a connection.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh from Bagoo'),
          ),
        ),
      ],
    );
  }
}
