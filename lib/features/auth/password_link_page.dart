import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'auth_shell.dart';

class PasswordLinkPage extends StatefulWidget {
  const PasswordLinkPage({
    super.key,
    required this.repository,
    required this.onComplete,
    this.initialLink,
  });
  final BuyerRepository repository;
  final VoidCallback onComplete;
  final Uri? initialLink;
  @override
  State<PasswordLinkPage> createState() => _PasswordLinkPageState();
}

class _PasswordLinkPageState extends State<PasswordLinkPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _link = TextEditingController(),
      _password = TextEditingController(),
      _confirmation = TextEditingController();
  String? _token, _error, _feedback;
  bool _busy = false, _paste = false;
  Map<String, String> _errors = {};
  @override
  void initState() {
    super.initState();
    if (widget.initialLink != null) {
      try {
        _accept(widget.initialLink!);
      } on BackendException catch (e) {
        _error = e.message;
        _paste = true;
      }
    }
  }

  void _accept(Uri link) {
    final target = widget.repository.session.resolve(link.toString());
    final parts = target.pathSegments;
    final email = target.queryParameters['email'] ?? '';
    if (parts.length != 2 ||
        parts.first != 'reset-password' ||
        !RegExp(r'^[a-zA-Z0-9_-]{10,512}$').hasMatch(parts.last) ||
        emailValidator(email) != null ||
        target.queryParameters['role'] != null &&
            target.queryParameters['role'] != 'buyer') {
      throw const BackendException(
        'Use the complete buyer password reset link from your email.',
      );
    }
    _token = parts.last;
    _email.text = email;
    _link.clear();
    _paste = false;
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _errors = {};
      _feedback = null;
    });
    try {
      if (_paste) {
        _accept(Uri.parse(_link.text.trim()));
        setState(() {});
      } else if (_token == null) {
        await widget.repository.sendPasswordLink(_email.text);
        if (mounted) {
          setState(
            () => _feedback = 'Bagoo confirmed that the reset email was sent. Open its buyer reset link or paste it here.',
          );
        }
      } else {
        await widget.repository.resetPasswordLink(
          _email.text,
          _token!,
          _password.text,
          _confirmation.text,
        );
        if (mounted) {
          _token = null;
          _password.clear();
          _confirmation.clear();
          widget.onComplete();
        }
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.fields.isEmpty ? e.message : e.fields.values.join('\n');
          _errors = e.fields;
        });
      }
    } on FormatException {
      if (mounted) {
        setState(() => _error = 'Use the complete reset link from your email.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _token = null;
    for (final controller in [_email, _link, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AuthShell(
      title: _token == null ? 'Recover with an email link' : 'Set new password',
      subtitle: 'Use the buyer password reset link sent by Bagoo. Links expire and are verified by the server.',
      onBack: () => Navigator.pop(context),
      onBrowse: () => Navigator.pop(context),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) Notice(_error!, error: true),
            if (_feedback != null) Notice(_feedback!),
            if (_paste)
              AuthField(
                label: 'Buyer password reset link',
                controller: _link,
                enabled: !_busy,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Paste the complete link.'
                    : null,
              )
            else
              AuthField(
                label: 'Recovery email address',
                controller: _email,
                enabled: !_busy && _token == null,
                keyboardType: TextInputType.emailAddress,
                validator: emailValidator,
                error: _errors['email'],
              ),
            if (_token != null) ...[
              AuthField(
                label: 'New password',
                controller: _password,
                enabled: !_busy,
                password: true,
                validator: passwordValidator,
                error: _errors['password'],
              ),
              AuthField(
                label: 'Confirm new password',
                controller: _confirmation,
                enabled: !_busy,
                password: true,
                validator: (value) =>
                    value == _password.text ? null : 'Passwords do not match.',
                error: _errors['password_confirmation'],
              ),
            ],
            SubmitButton(
              label: _paste
                  ? 'Continue with link'
                  : _token == null
                  ? 'Send password reset link'
                  : 'Save new password',
              busy: _busy,
              onPressed: _submit,
            ),
            if (_token == null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _paste = !_paste;
                        _error = null;
                      }),
                child: Text(
                  _paste ? 'Request a reset email' : 'Paste a reset link',
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
