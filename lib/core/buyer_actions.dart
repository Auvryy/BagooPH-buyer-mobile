import 'package:flutter/material.dart';

class BuyerActions extends InheritedWidget {
  const BuyerActions({
    super.key,
    required this.signIn,
    required super.child,
    this.signInTo,
    this.sessionEnded,
    this.openVerification,
  });
  final void Function(String? productSlug) signIn;
  final void Function(String destination)? signInTo;
  final VoidCallback? sessionEnded;
  final VoidCallback? openVerification;
  static void endSession(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BuyerActions>()
      ?.sessionEnded
      ?.call();
  static void reviewVerification(BuildContext context) {
    final action = context
        .dependOnInheritedWidgetOfExactType<BuyerActions>()
        ?.openVerification;
    if (action != null) {
      action();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open Profile to review your verification.'),
        ),
      );
    }
  }

  static void login(
    BuildContext context, {
    String? productSlug,
    String? destination,
  }) {
    final actions = context.dependOnInheritedWidgetOfExactType<BuyerActions>();
    if (actions != null) {
      if (destination != null && actions.signInTo != null) {
        actions.signInTo!(destination);
      } else {
        actions.signIn(productSlug);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in with a buyer account.')),
      );
    }
  }

  @override
  bool updateShouldNotify(BuyerActions oldWidget) =>
      oldWidget.signIn != signIn ||
      oldWidget.signInTo != signInTo ||
      oldWidget.sessionEnded != sessionEnded ||
      oldWidget.openVerification != openVerification;
}
