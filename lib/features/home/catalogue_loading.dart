import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'product_card.dart';

class CatalogueLoadingGrid extends StatelessWidget {
  const CatalogueLoadingGrid({
    super.key,
    required this.columns,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });
  final int columns;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: padding,
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.crossAxisExtent - (columns - 1) * 14) / columns;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return SliverGrid.builder(
          itemCount: columns * 2,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: width + productCardBodyHeight * scale,
          ),
          itemBuilder: (_, index) => Semantics(
            label: index == 0 ? 'Loading products' : null,
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(BagooTheme.panelRadius),
                border: Border.all(color: BagooTheme.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(BagooTheme.panelRadius),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bar(double.infinity, 14),
                        const SizedBox(height: 10),
                        _bar(width * .6, 14),
                        const SizedBox(height: 16),
                        _bar(width * .5, 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _bar(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFE2E8F0),
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
