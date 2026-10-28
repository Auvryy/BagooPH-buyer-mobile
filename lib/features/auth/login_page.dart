import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'auth_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.repository,
    required this.onAuthenticated,
    required this.onRegister,
    required this.onForgot,
    required this.onBrowse,
    this.notice,
  });
  final BuyerRepository repository;
  final ValueChanged<WebPage> onAuthenticated;
  final VoidCallback onRegister;
  final VoidCallback onForgot;
  final VoidCallback onBrowse;
  final String? notice;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _summary = GlobalKey();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _remember = false;
  String? _error;
  Map<String, String> _errors = {};
  @override
  void initState() {
    super.initState();
    _email.text = widget.repository.session.rememberedEmail ?? '';
    _remember = widget.repository.session.remembersLogin;
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    setState(() {
      _errors = {};
      _error = null;
    });
    if (!_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final page = await widget.repository.login(
        _email.text,
        _password.text,
        remember: _remember,
      );
      if (!mounted) {
        return;
      }
      TextInput.finishAutofillContext();
      if (_remember && !widget.repository.session.persistenceAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You are signed in. This device could not save your session; sign in again after closing the app.',
            ),
          ),
        );
      }
      widget.onAuthenticated(page);
    } on BackendException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.fields.isEmpty
            ? error.message
            : error.fields.values.toSet().join('\n');
        _errors = error.fields;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_summary.currentContext != null) {
          Scrollable.ensureVisible(_summary.currentContext!);
        }
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthShell(
    title: 'Log In',
    subtitle: 'Enter your email and password to access your account.',
    onBrowse: widget.onBrowse,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Notice(widget.notice!),
            ),
          if (_error != null)
            Padding(
              key: _summary,
              padding: const EdgeInsets.only(bottom: 20),
              child: Notice(_error!, error: true),
            ),
          AuthField(
            label: 'Email address',
            controller: _email,
            enabled: !_busy,
            hint: 'name@example.com',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            validator: emailValidator,
            error: _errors['email'],
            onChanged: (_) => setState(() => _errors.remove('email')),
          ),
          AuthField(
            label: 'Password',
            controller: _password,
            enabled: !_busy,
            password: true,
            icon: Icons.lock_outline_rounded,
            autofillHints: const [AutofillHints.password],
            validator: (v) =>
                v == null || v.isEmpty ? 'Enter your password.' : null,
            error: _errors['password'],
            onChanged: (_) => setState(() => _errors.remove('password')),
            onSubmitted: (_) => _submit(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : widget.onForgot,
              child: const Text('Forgot password?'),
            ),
          ),
          CheckboxListTile(
            value: _remember,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Remember me on this device'),
            onChanged: _busy
                ? null
                : (value) => setState(() => _remember = value ?? false),
          ),
          const SizedBox(height: 12),
          SubmitButton(
            label: _busy ? 'Signing in…' : 'Log In',
            busy: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                "Don't have an account?",
                style: TextStyle(fontSize: 13),
              ),
              TextButton(
                onPressed: _busy ? null : widget.onRegister,
                child: const Text('Sign Up'),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : widget.onBrowse,
            icon: const Icon(Icons.storefront_outlined, size: 20),
            label: const Text('Browse the marketplace'),
          ),
        ],
      ),
    ),
  );
}
