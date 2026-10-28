import 'package:flutter/material.dart';

import '../app/theme.dart';

class CachedCatalogueNotice extends StatelessWidget {
  const CachedCatalogueNotice({
    super.key,
    required this.savedAt,
    required this.onRefresh,
    this.refreshing = false,
  });
  final DateTime savedAt;
  final VoidCallback? onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final date = savedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final recorded =
        '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BagooTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: BagooTheme.muted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        refreshing
                            ? 'Showing saved products · refreshing…'
                            : 'Saved browsing data',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                        ),
                      ),
                      Text(
                        'Saved $recorded',
                        style: const TextStyle(
                          fontSize: 12,
                          color: BagooTheme.muted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!refreshing) ...[
              const SizedBox(height: 8),
              const Text(
                'Prices and availability may have changed. Refresh before shopping.',
                style: TextStyle(
                  fontSize: 13,
                  color: BagooTheme.muted,
                  height: 1.5,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh from Bagoo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
