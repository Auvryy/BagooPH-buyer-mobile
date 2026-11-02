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
    this.focusNode,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilters;
  final String? filterLabel;
  final bool clearable;
  final bool showFilters;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final textScale = MediaQuery.textScalerOf(context).scale(16);
      final compact = box.maxWidth < 280;
      final compactLabel = compact && textScale > 24 ? 'Search' : label;
      final search = TextField(
        controller: controller,
        focusNode: focusNode,
        maxLength: 100,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: compactLabel,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          hintText: compact ? 'Find' : 'Find products',
          counterText: '',
          isDense: compact,
          contentPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
              : null,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          prefixIconConstraints: compact
              ? const BoxConstraints(minWidth: 40, minHeight: 48)
              : null,
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
          suffixIconConstraints: compact
              ? const BoxConstraints(minWidth: 48, minHeight: 48)
              : null,
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
                minimumSize: Size(compact ? 48 : 56, compact ? 48 : 56),
                padding: EdgeInsets.zero,
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
      if (textScale > 24 || box.maxWidth < 232) {
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
