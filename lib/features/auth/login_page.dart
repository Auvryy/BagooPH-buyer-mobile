import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'auth_shell.dart';
import 'native_google_sign_in.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.repository,
    required this.onAuthenticated,
    required this.onGoogleRegistration,
    required this.onRegister,
    required this.onForgot,
    required this.onBrowse,
    this.notice,
  });
  final BuyerRepository repository;
  final ValueChanged<WebPage> onAuthenticated;
  final ValueChanged<GoogleRegistrationChallenge> onGoogleRegistration;
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
  String? _error;
  Map<String, String> _errors = {};
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
      final page = await widget.repository.login(_email.text, _password.text);
      if (!mounted) {
        return;
      }
      TextInput.finishAutofillContext();
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

  Future<void> _googleSignIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _errors = {};
    });
    try {
      final token = await NativeGoogleSignIn.instance.requestIdToken();
      if (!mounted || token == null) return;
      final result = await widget.repository.signInWithGoogle(token);
      if (!mounted) return;
      final page = result.page;
      final registration = result.registration;
      if (page != null) {
        widget.onAuthenticated(page);
      } else if (registration != null) {
        widget.onGoogleRegistration(registration);
      } else {
        setState(() {
          _error = 'Bagoo could not confirm Google sign-in. Please try again.';
        });
      }
    } on BackendException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Google sign-in could not finish. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
          const SizedBox(height: 12),
          SubmitButton(
            label: _busy ? 'Signing in…' : 'Log In',
            busy: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: 14),
          if (NativeGoogleSignIn.isSupported)
            OutlinedButton(
              onPressed: _busy ? null : _googleSignIn,
              child: const Text('Continue with Google'),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Google sign-in is available in the Android and iOS apps.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
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
