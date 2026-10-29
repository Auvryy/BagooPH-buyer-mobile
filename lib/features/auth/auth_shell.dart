import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/contact_input.dart';
import '../../core/widgets.dart';
export '../../core/auth_validation.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onBrowse,
    this.registration = false,
    this.onBack,
    this.navigationEnabled = true,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback onBrowse;
  final VoidCallback? onBack;
  final bool navigationEnabled;
  final bool registration;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 900 &&
              constraints.maxHeight >= 600 &&
              MediaQuery.textScalerOf(context).scale(16) <= 24;
          final form = SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 48 : 24,
              vertical: 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        children: [
                          const Brand(),
                          TextButton(
                            onPressed: navigationEnabled ? onBrowse : null,
                            child: const Text('Marketplace'),
                          ),
                        ],
                      ),
                      SizedBox(height: wide ? 64 : 36),
                      if (onBack != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: navigationEnabled ? onBack : null,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                            ),
                            label: const Text('Back to log in'),
                          ),
                        ),
                      const Text(
                        'BUYER MARKETPLACE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                          color: BagooTheme.strong,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 32,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: BagooTheme.muted,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      child,
                      const SizedBox(height: 32),
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text(
                          'Local finds. Everyday value. BagooPH.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: BagooTheme.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          final panes = <Widget>[
            Expanded(flex: 5, child: form),
            if (wide)
              Expanded(
                flex: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      registration
                          ? 'assets/auth/buyer_register.jpg'
                          : 'assets/auth/buyer_login.jpg',
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(40),
                        color: BagooTheme.ink.withValues(alpha: .9),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'BUYER MARKETPLACE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              registration
                                  ? 'Your next great find starts here.'
                                  : 'Everyday Value,\nDelivered Direct',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Discover local stores, everyday essentials, and a simpler way to shop.',
                              style: TextStyle(
                                color: Colors.white,
                                height: 1.6,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ];
          return Row(children: registration ? panes.reversed.toList() : panes);
        },
      ),
    ),
  );
}

class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.password = false,
    this.error,
    this.validator,
    this.keyboardType,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.readOnly = false,
    this.onTap,
    this.maxLength,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final bool password;
  final String? error;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;
  final VoidCallback? onTap;
  final int? maxLength;
  final bool enabled;
  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _visible = false;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      obscureText: widget.password && !_visible,
      enableSuggestions: !widget.password,
      autocorrect: !widget.password,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.keyboardType == TextInputType.phone
          ? [mobileNumberFormatter]
          : null,
      autofillHints: widget.autofillHints,
      maxLength: widget.maxLength,
      style: const TextStyle(fontSize: 16),
      validator: (value) =>
          widget.validator?.call(value) ??
          (widget.keyboardType == TextInputType.phone
              ? mobileNumberValidator(value)
              : null),
      forceErrorText: widget.error,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      textInputAction: widget.onSubmitted != null
          ? TextInputAction.done
          : TextInputAction.next,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        alignLabelWithHint: true,
        prefixIcon: widget.icon == null
            ? null
            : ExcludeSemantics(child: Icon(widget.icon, size: 20)),
        suffixIcon: widget.password
            ? IconButton(
                tooltip: _visible ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _visible = !_visible),
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              )
            : null,
      ),
    ),
  );
}
