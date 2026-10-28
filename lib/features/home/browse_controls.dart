import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'search_controller.dart';

class BrowseSearchField extends StatelessWidget {
  const BrowseSearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.onSubmitted,
    this.onChanged,
    this.onFilters,
    this.filterLabel,
    this.clearable = false,
    this.showFilters = true,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilters;
  final String? filterLabel;
  final bool clearable;
  final bool showFilters;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final search = TextField(
        controller: controller,
        maxLength: 100,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          hintText: 'Find products',
          counterText: '',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: clearable && controller.text.isNotEmpty
                ? 'Clear search'
                : 'Search products',
            onPressed: () {
              if (clearable && controller.text.isNotEmpty) controller.clear();
              onSubmitted(controller.text);
            },
            icon: Icon(
              clearable && controller.text.isNotEmpty
                  ? Icons.close
                  : Icons.arrow_forward_rounded,
            ),
          ),
        ),
      );
      if (!showFilters) return search;
      final Widget filter =
          filterLabel == null ||
              box.maxWidth < 400 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24
          ? IconButton.outlined(
              tooltip: filterLabel ?? 'Filter products',
              onPressed: onFilters,
              style: IconButton.styleFrom(
                minimumSize: const Size(56, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BagooTheme.controlRadius),
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
            )
          : Tooltip(
              message: filterLabel!,
              child: OutlinedButton.icon(
                onPressed: onFilters,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(filterLabel!),
              ),
            );
      if (MediaQuery.textScalerOf(context).scale(16) > 24 ||
          box.maxWidth < 280) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: filter),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 8),
          filter,
        ],
      );
    },
  );
}

Future<String?> showBuyerSort(BuildContext context, String value) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => SizedBox(
      height: math.min(440, MediaQuery.sizeOf(sheet).height * .75),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Semantics(
              header: true,
              child: const Text(
                'Sort products',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              children: [
                for (final sort in searchSorts.entries)
                  Semantics(
                    selected: sort.key == value,
                    child: ListTile(
                      title: Text(sort.value),
                      selected: sort.key == value,
                      selectedColor: BagooTheme.strong,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      trailing: sort.key == value
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(sheet, sort.key),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
