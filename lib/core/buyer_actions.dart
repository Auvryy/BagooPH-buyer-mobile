import 'package:flutter/material.dart';

class BuyerActions extends InheritedWidget {
  const BuyerActions({super.key, required this.signIn, required super.child});
  final void Function(String? productSlug) signIn;
  static void login(BuildContext context, {String? productSlug}) {
    final actions = context.dependOnInheritedWidgetOfExactType<BuyerActions>();
    if (actions != null) {
      actions.signIn(productSlug);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in with a buyer account.')),
      );
    }
  }

  @override
  bool updateShouldNotify(BuyerActions oldWidget) => oldWidget.signIn != signIn;
}
