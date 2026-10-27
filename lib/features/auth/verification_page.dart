import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
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
      cooldown: (sent['cooldown'] as num?)?.toInt() ?? 60,
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
  Timer? _timer;
  late int _remaining;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _remaining = widget.cooldown;
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 0) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _verify() async {
    if (_busy || !_form.currentState!.validate()) {
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
        setState(() => _error = error.fields['code'] ?? error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resend() async {
    if (_busy || _remaining > 0) {
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
      setState(() {
        _remaining = (result['cooldown'] as num?)?.toInt() ?? 60;
        _code.clear();
      });
      _tick();
    } on BackendException catch (error) {
      if (mounted) {
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
    _timer?.cancel();
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
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                label: _busy ? 'Verifying…' : 'Verify email',
                busy: _busy,
                onPressed: _verify,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _busy || _remaining > 0 ? null : _resend,
                child: Text(
                  _remaining > 0
                      ? 'Resend code in ${_remaining}s'
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
