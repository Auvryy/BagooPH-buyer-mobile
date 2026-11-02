import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/retry_cooldown.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'auth_shell.dart';
import 'verification_page.dart';
import 'password_link_page.dart';

class RecoveryPage extends StatefulWidget {
  const RecoveryPage({
    super.key,
    required this.repository,
    required this.onBack,
    required this.onBrowse,
    required this.onComplete,
  });
  final BuyerRepository repository;
  final VoidCallback onBack;
  final VoidCallback onBrowse;
  final VoidCallback onComplete;
  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _token;
  String? _error;
  Map<String, String> _errors = {};
  late final RetryCooldown _codeCooldown;
  late final RetryCooldown _resetCooldown;

  @override
  void initState() {
    super.initState();
    void changed() {
      if (mounted) setState(() {});
    }

    _codeCooldown = RetryCooldown(changed);
    _resetCooldown = RetryCooldown(changed);
  }

  Future<void> _submit() async {
    if (_busy ||
        (_token == null && _codeCooldown.active) ||
        (_token != null && _resetCooldown.active)) {
      return;
    }
    setState(() {
      _error = null;
      _errors = {};
    });
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() => _busy = true);
    FocusScope.of(context).unfocus();
    try {
      if (_token == null) {
        final sent = await widget.repository.sendCode(
          _email.text,
          'password_reset',
        );
        if (!mounted) {
          return;
        }
        _codeCooldown.start(sent);
        final token = await verifyEmailCode(
          context,
          widget.repository,
          _email.text,
          'password_reset',
          sent,
        );
        if (mounted && token != null) {
          setState(() => _token = token);
        }
      } else {
        await widget.repository.resetPassword(
          _email.text,
          _token!,
          _password.text,
          _confirmation.text,
        );
        if (mounted) {
          widget.onComplete();
        }
      }
    } on BackendException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.status == 429) {
        if (_token == null) {
          _codeCooldown.start(error.data, retryAt: error.retryAt);
        } else {
          _resetCooldown.start(error.data, retryAt: error.retryAt);
        }
      }
      setState(() {
        _error = error.fields.isEmpty
            ? error.message
            : error.fields.values.toSet().join('\n');
        _errors = error.fields;
        if (error.fields.containsKey('token') ||
            error.fields.containsKey('code')) {
          _token = null;
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
    _codeCooldown.dispose();
    _resetCooldown.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthShell(
    title: _token == null ? 'Reset Password' : 'Set New Password',
    subtitle: _token == null
        ? 'Verify your identity with a 6-digit code sent to your email.'
        : 'Choose a strong password for your buyer account.',
    onBack: widget.onBack,
    onBrowse: widget.onBrowse,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Notice(_error!, error: true),
            ),
          if (_token == null)
            AuthField(
              label: 'Registered email address',
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              icon: Icons.mail_outline_rounded,
              validator: emailValidator,
              error: _errors['email'],
              onChanged: (_) => setState(() => _errors.remove('email')),
              onSubmitted: (_) => _submit(),
            )
          else ...[
            Notice('Email verified: ${_email.text.trim()}'),
            const SizedBox(height: 24),
            AuthField(
              label: 'New password',
              controller: _password,
              enabled: !_busy,
              password: true,
              autofillHints: const [AutofillHints.newPassword],
              validator: passwordValidator,
              error: _errors['password'],
              onChanged: (_) => setState(() => _errors.remove('password')),
            ),
            AuthField(
              label: 'Confirm new password',
              controller: _confirmation,
              enabled: !_busy,
              password: true,
              validator: (v) =>
                  v == _password.text ? null : 'Passwords do not match.',
              error: _errors['password_confirmation'],
              onChanged: (_) =>
                  setState(() => _errors.remove('password_confirmation')),
              onSubmitted: (_) => _submit(),
            ),
          ],
          SubmitButton(
            label: _token == null
                ? _codeCooldown.active
                      ? 'Send code in ${_codeCooldown.remainingSeconds}s'
                      : 'Send verification code'
                : _resetCooldown.active
                ? 'Try again in ${_resetCooldown.remainingSeconds}s'
                : 'Save new password',
            busy: _busy,
            onPressed: _token == null
                ? _codeCooldown.active
                      ? null
                      : _submit
                : _resetCooldown.active
                ? null
                : _submit,
          ),
          if (_token == null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (routeContext) => PasswordLinkPage(
                          repository: widget.repository,
                          onComplete: () {
                            Navigator.pop(routeContext);
                            widget.onComplete();
                          },
                        ),
                      ),
                    ),
              child: const Text('Recover with an email link'),
            ),
        ],
      ),
    ),
  );
}
