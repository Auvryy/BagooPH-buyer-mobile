import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'auth_shell.dart';
import 'google_auth_page.dart';
import 'google_auth_repository.dart';
import 'google_identity.dart';
import 'native_google_identity.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.repository,
    required this.onAuthenticated,
    required this.onRegister,
    required this.onForgot,
    required this.onBrowse,
    this.notice,
    this.googleProvider,
    this.onProviderFlowChanged,
  });
  final BuyerRepository repository;
  final ValueChanged<WebPage> onAuthenticated;
  final VoidCallback onRegister;
  final VoidCallback onForgot;
  final VoidCallback onBrowse;
  final String? notice;
  final GoogleIdentityProvider? googleProvider;
  final ValueChanged<bool>? onProviderFlowChanged;
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
  late final GoogleIdentityProvider _googleProvider;
  late final GoogleAuthRepository _googleAuth;
  bool _googleAvailable = false;
  Timer? _googleCooldown;
  @override
  void initState() {
    super.initState();
    _email.text = widget.repository.session.rememberedEmail ?? '';
    _remember = widget.repository.session.remembersLogin;
    _googleProvider = widget.googleProvider ?? NativeGoogleIdentityProvider();
    _googleAuth = GoogleAuthRepository(widget.repository);
    if (_googleProvider.isAvailable) unawaited(_loadGoogle());
  }

  Future<void> _loadGoogle() async {
    final epoch = widget.repository.session.identityEpoch;
    final capabilities = await widget.repository.discoverCapabilities();
    if (mounted && epoch == widget.repository.session.identityEpoch) {
      setState(() => _googleAvailable = capabilities.nativeGoogleSignIn);
    }
  }

  Future<void> _googleSignIn() async {
    if (_busy ||
        !_googleAvailable ||
        _googleAuth.retryAt?.isAfter(DateTime.now()) == true) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    widget.onProviderFlowChanged?.call(true);
    try {
      final result = await Navigator.of(context).push<GoogleAuthExit>(
        MaterialPageRoute(
          builder: (_) => GoogleAuthPage(
            repository: _googleAuth,
            provider: _googleProvider,
            remember: _remember,
          ),
        ),
      );
      if (!mounted) return;
      if (result?.page != null) {
        if (_remember && !widget.repository.session.persistenceAvailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You are signed in. This device could not save your session; sign in again after closing the app.',
              ),
            ),
          );
        }
        widget.onAuthenticated(result!.page!);
      } else if (result?.browse == true) {
        widget.onBrowse();
      }
    } finally {
      widget.onProviderFlowChanged?.call(false);
      if (mounted) {
        setState(() => _busy = false);
        final deadline = _googleAuth.retryAt;
        if (deadline != null && deadline.isAfter(DateTime.now())) {
          _googleCooldown?.cancel();
          _googleCooldown = Timer(deadline.difference(DateTime.now()), () {
            if (mounted) setState(() {});
          });
        }
      }
    }
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
    _googleCooldown?.cancel();
    _googleAuth.abandon();
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
          if (_googleAvailable) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('continue-with-google'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F1F1F),
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: Color(0xFF747775)),
              ),
              onPressed:
                  _busy || _googleAuth.retryAt?.isAfter(DateTime.now()) == true
                  ? null
                  : _googleSignIn,
              icon: Image.asset(
                'assets/auth/google-g.png',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              label: const Text('Continue with Google'),
            ),
            if (_googleAuth.retryAt?.isAfter(DateTime.now()) == true)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Please wait before trying Google again. Email sign-in remains available.',
                ),
              ),
          ],
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
