import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/numeric_input.dart';
import '../../core/retry_cooldown.dart';
import '../../core/verification_cooldown.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';

/// Returns a server-issued verification token. Never accepts a local code.
Future<String?> verifyEmailCode(
  BuildContext context,
  BuyerRepository repository,
  String email,
  String purpose,
  Map<String, dynamic> sent,
) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => VerificationPage(
      repository: repository,
      email: email,
      purpose: purpose,
      cooldown: verificationCooldownSeconds(sent),
    ),
  ),
);

class VerificationPage extends StatefulWidget {
  const VerificationPage({
    super.key,
    required this.repository,
    required this.email,
    required this.purpose,
    required this.cooldown,
  });
  final BuyerRepository repository;
  final String email;
  final String purpose;
  final int cooldown;
  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final RetryCooldown _sendCooldown, _verifyCooldown;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    void changed() {
      if (mounted) setState(() {});
    }

    _sendCooldown = RetryCooldown(changed);
    _verifyCooldown = RetryCooldown(changed);
    _sendCooldown.startFor(Duration(seconds: widget.cooldown), notify: false);
  }

  Future<void> _verify() async {
    if (_busy || _verifyCooldown.active || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await widget.repository.verifyCode(
        widget.email,
        widget.purpose,
        _code.text,
      );
      if (mounted) {
        Navigator.of(context).pop(token);
      }
    } on BackendException catch (error) {
      if (mounted) {
        if (error.status == 429) {
          _verifyCooldown.start(error.data, retryAt: error.retryAt);
        }
        setState(() => _error = error.fields['code'] ?? error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resend() async {
    if (_busy || _sendCooldown.active) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.sendCode(
        widget.email,
        widget.purpose,
        resend: true,
      );
      if (!mounted) {
        return;
      }
      _sendCooldown.start(result);
      setState(_code.clear);
    } on BackendException catch (error) {
      if (mounted) {
        if (error.status == 429) {
          _sendCooldown.start(error.data, retryAt: error.retryAt);
        }
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _sendCooldown.dispose();
    _verifyCooldown.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(title: const Text('Verify your email')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: BagooTheme.rose,
                  child: Icon(
                    Icons.mark_email_read_outlined,
                    size: 28,
                    color: BagooTheme.strong,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Check your inbox',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Enter the 6-digit code sent to ${widget.email}. Check your spam folder too.',
                style: const TextStyle(color: BagooTheme.muted, height: 1.6),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Notice(_error!, error: true),
                ),
              Form(
                key: _form,
                child: TextFormField(
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [unsignedIntegerFormatter],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _verify(),
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 10,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    counterText: '',
                  ),
                  validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '')
                      ? null
                      : 'Enter all 6 digits.',
                ),
              ),
              const SizedBox(height: 24),
              SubmitButton(
                label: _verifyCooldown.active
                    ? 'Verify in ${_verifyCooldown.remainingSeconds}s'
                    : _busy
                    ? 'Verifying…'
                    : 'Verify email',
                busy: _busy,
                onPressed: _verifyCooldown.active ? null : _verify,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _busy || _sendCooldown.active ? null : _resend,
                child: Text(
                  _sendCooldown.active
                      ? 'Resend code in ${_sendCooldown.remainingSeconds}s'
                      : 'Resend code',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Use a different email'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
