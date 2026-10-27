import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

class EmailSection extends StatefulWidget {
  const EmailSection({
    super.key,
    required this.repository,
    required this.page,
    required this.reload,
  });
  final ProfileRepository repository;
  final WebPage page;
  final Future<void> Function() reload;
  @override
  State<EmailSection> createState() => _EmailSectionState();
}

class _EmailSectionState extends ProfileFormState<EmailSection> {
  final _password = TextEditingController(),
      _email = TextEditingController(),
      _code = TextEditingController();
  bool _sent = false;
  String? _sentTo;
  DateTime? _until;
  int _cooldown = 0;
  Timer? _timer;
  Map<String, dynamic> get settings =>
      mapOf(widget.page.props['emailSettings']);
  void _wait(int seconds) {
    _until = DateTime.now().add(Duration(seconds: seconds));
    _cooldown = seconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(
        () => _cooldown =
            (_until!.difference(DateTime.now()).inMilliseconds / 1000)
                .ceil()
                .clamp(0, 3600),
      );
      if (_cooldown == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_password, _email, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _action(String action, [Map<String, dynamic>? address]) async {
    if ((action == 'remove' || action == 'prefer') &&
        !await confirmAction(
          context,
          action == 'remove'
              ? 'Remove this recovery email?'
              : 'Use this contact email?',
          '${address?['email']}\nYour original sign-in email stays unchanged.',
          action == 'remove' ? 'Remove email' : 'Use for contact',
        )) {
      return;
    }
    await perform(() async {
      if (_password.text.isEmpty) {
        throw const BackendException(
          'Enter your current password.',
          fields: {'current_password': 'Confirm your current password.'},
        );
      }
      final values = {
        'current_password': _password.text,
        'email': _email.text.trim(),
        if (action == 'confirm') 'code': _code.text,
      };
      Map<String, dynamic> data;
      try {
        data = await widget.repository.json(
          switch (action) {
            'send' => '/account/emails/send',
            'confirm' => '/account/emails/confirm',
            'prefer' => '/account/emails/${address!['id']}/preferred',
            _ => '/account/emails/${address!['id']}',
          },
          values,
          method: action == 'prefer'
              ? 'PATCH'
              : action == 'remove'
              ? 'DELETE'
              : 'POST',
        );
      } on BackendException catch (e) {
        if (e.status == 429 && mounted) _wait(60);
        rethrow;
      }
      if (action == 'send') {
        if (data['success'] != true) {
          throw const BackendException(
            'The verification email was not confirmed.',
          );
        }
        _sent = true;
        _sentTo = _email.text.trim();
        _wait((data['cooldown'] as num?)?.ceil() ?? 60);
      } else {
        if (data['message'] is! String) {
          throw const BackendException('The email change was not confirmed.');
        }
        _password.clear();
        _email.clear();
        _code.clear();
        _sent = false;
        _sentTo = null;
        await widget.reload();
      }
      return data['message']?.toString() ??
          'A code was sent to your additional email.';
    }, validate: action == 'send' || action == 'confirm');
  }

  @override
  Widget build(BuildContext context) => content([
    const ProfileHeading(
      'Email and recovery',
      'Keep your original sign-in email. Add and verify another address for contact and password recovery.',
      Icons.mail_outline,
    ),
    for (final address in mapsOf(settings['addresses']))
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              address['email']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              '${address['is_original'] == true ? 'Original sign-in email' : 'Additional email'} · ${address['verified'] == true ? 'Verified' : 'Verification required'}${address['preferred'] == true ? ' · Contact email' : ''}',
              style: const TextStyle(fontSize: 12, height: 1.7),
            ),
            if (settings['can_manage'] == true)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (address['verified'] == true &&
                      address['preferred'] != true)
                    TextButton(
                      onPressed: busy ? null : () => _action('prefer', address),
                      child: const Text('Use for contact'),
                    ),
                  if (address['is_original'] != true)
                    TextButton(
                      onPressed: busy ? null : () => _action('remove', address),
                      child: const Text('Remove email'),
                    ),
                ],
              ),
            const Divider(),
          ],
        ),
      ),
    if (settings['can_manage'] == true) ...[
      field(
        'current_password',
        'Current password',
        _password,
        secret: true,
        max: 4096,
        autofill: const [AutofillHints.password],
        hint: 'Required to add, remove or choose a contact email.',
      ),
      field(
        'email',
        'Additional email',
        _email,
        max: 255,
        keyboard: TextInputType.emailAddress,
        autofill: const [AutofillHints.email],
        check: (value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)
            ? null
            : 'Enter a valid email address.',
        onChanged: (_) {
          if (_sent) {
            setState(() {
              _sent = false;
              _sentTo = null;
              _code.clear();
            });
          }
        },
      ),
      if (_sent)
        field(
          'code',
          'Verification code',
          _code,
          max: 6,
          keyboard: TextInputType.number,
          autofill: const [AutofillHints.oneTimeCode],
          hint:
              'Six-digit code sent to $_sentTo. It expires after ten minutes.',
          check: (value) => RegExp(r'^\d{6}$').hasMatch(value)
              ? null
              : 'Enter the six-digit code.',
        ),
      SubmitButton(
        label: _sent
            ? 'Verify and add email'
            : _cooldown > 0
            ? 'Send code in ${_cooldown}s'
            : 'Send verification code',
        busy: busy,
        onPressed: !_sent && _cooldown > 0
            ? null
            : () => _action(_sent ? 'confirm' : 'send'),
      ),
      if (_sent)
        TextButton(
          onPressed: busy || _cooldown > 0 ? null : () => _action('send'),
          child: Text(
            _cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend code',
          ),
        ),
    ] else
      const Notice(
        'An active approved account is required to manage recovery emails.',
      ),
  ]);
}
