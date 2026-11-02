import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/resource_ids.dart';
import '../../core/retry_cooldown.dart';
import '../../core/web_session.dart';
import '../../core/verification_cooldown.dart';
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

class _EmailSectionState extends BuyerProfileFormState<EmailSection> {
  @override
  ProfileRepository get accountRepository => widget.repository;
  @override
  WebPage get accountPage => widget.page;
  final _password = TextEditingController(),
      _email = TextEditingController(),
      _code = TextEditingController();
  late final RetryCooldown _verifyCooldown;
  final Map<String, RetryCooldown> _addressCooldowns = {};
  bool _sent = false;
  String? _sentTo;
  DateTime? _until;
  int _cooldown = 0;
  Timer? _timer;
  Map<String, dynamic> get settings =>
      mapOf(widget.page.props['emailSettings']);

  @override
  void initState() {
    super.initState();
    _verifyCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
  }

  String? _addressCooldownKey(String action, Map<String, dynamic>? address) {
    if (action != 'remove' && action != 'prefer') return null;
    final id = positiveResourceId(address?['id']);
    return id == null ? null : action;
  }

  List<Map<String, dynamic>>? get _validatedAddresses {
    final original = settings['original'];
    final raw = settings['addresses'];
    if (original is! String || original.trim().isEmpty || raw is! List) {
      return null;
    }
    final rows = mapsOf(raw);
    final ids = <int>{};
    if (rows.isEmpty ||
        rows.length != raw.length ||
        rows.any((row) {
          final id = positiveResourceId(row['id']);
          return id == null ||
              !ids.add(id) ||
              row['email'] is! String ||
              (row['email'] as String).trim().isEmpty ||
              row['is_original'] is! bool ||
              row['verified'] is! bool ||
              row['preferred'] is! bool;
        })) {
      return null;
    }
    final originals = rows.where((row) => row['is_original'] == true).toList();
    final preferred = rows.where((row) => row['preferred'] == true).toList();
    if (originals.length != 1 ||
        preferred.length != 1 ||
        originals.single['email'] != original) {
      return null;
    }
    return rows;
  }

  bool _canChangeAddress(String action, Map<String, dynamic>? address) {
    final id = positiveResourceId(address?['id']);
    final current = _validatedAddresses
        ?.where((row) => row['id'] == id)
        .firstOrNull;
    if (id == null || current == null) return false;
    return switch (action) {
      'remove' => current['is_original'] == false,
      'prefer' => current['verified'] == true && current['preferred'] == false,
      _ => false,
    };
  }

  @override
  void clearBuyerDraft() {
    _timer?.cancel();
    _verifyCooldown.clear(notify: false);
    for (final cooldown in _addressCooldowns.values) {
      cooldown.dispose();
    }
    _addressCooldowns.clear();
    _until = null;
    _cooldown = 0;
    _sent = false;
    _sentTo = null;
    _password.clear();
    _email.clear();
    _code.clear();
  }

  void _wait(Map<String, dynamic> data, {DateTime? retryAt}) {
    _until = verificationCooldownDeadline(data, retryAt: retryAt);
    _cooldown = (_until!.difference(DateTime.now()).inMilliseconds / 1000)
        .ceil()
        .clamp(0, 3600);
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
    _verifyCooldown.dispose();
    for (final cooldown in _addressCooldowns.values) {
      cooldown.dispose();
    }
    for (final c in [_password, _email, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _action(String action, [Map<String, dynamic>? address]) async {
    final addressCooldownKey = _addressCooldownKey(action, address);
    if ((action == 'send' && _cooldown > 0) ||
        (action == 'confirm' && _verifyCooldown.active) ||
        (_addressCooldowns[addressCooldownKey]?.active ?? false) ||
        !ensureBuyerAccess() ||
        (action == 'remove' || action == 'prefer') &&
            !_canChangeAddress(action, address)) {
      return;
    }
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
    if (!ensureBuyerAccess() ||
        (action == 'send' && _cooldown > 0) ||
        (action == 'confirm' && _verifyCooldown.active) ||
        (_addressCooldowns[addressCooldownKey]?.active ?? false) ||
        (action == 'remove' || action == 'prefer') &&
            !_canChangeAddress(action, address)) {
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
      if (action == 'confirm' && (!_sent || _sentTo != _email.text.trim())) {
        _sent = false;
        _sentTo = null;
        _code.clear();
        throw const BackendException(
          'The additional email changed. Request a new code for this address.',
        );
      }
      Map<String, dynamic> data;
      try {
        data = await widget.repository.json(
          switch (action) {
            'send' => '/account/emails/send',
            'confirm' => '/account/emails/confirm',
            'prefer' =>
              '/account/emails/${positiveResourceId(address!['id'])!}/preferred',
            _ => '/account/emails/${positiveResourceId(address!['id'])!}',
          },
          values,
          method: action == 'prefer'
              ? 'PATCH'
              : action == 'remove'
              ? 'DELETE'
              : 'POST',
        );
        checkBuyerAccount();
      } on BackendException catch (e) {
        if (e.status == 429 && mounted) {
          if (action == 'send') {
            _wait(e.data, retryAt: e.retryAt);
          } else if (action == 'confirm') {
            _verifyCooldown.start(e.data, retryAt: e.retryAt, notify: false);
          } else if (addressCooldownKey != null) {
            final cooldown = _addressCooldowns.putIfAbsent(
              addressCooldownKey,
              () => RetryCooldown(() {
                if (mounted) setState(() {});
              }),
            );
            cooldown.start(e.data, retryAt: e.retryAt, notify: false);
          }
        }
        rethrow;
      }
      if (action == 'send') {
        if (data['success'] != true) {
          throw const BackendException(
            'The verification email was not confirmed.',
          );
        }
        _sent = true;
        _sentTo = values['email'];
        _wait(data);
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
  Widget build(BuildContext context) {
    final addresses = _validatedAddresses;
    return content([
      const ProfileHeading(
        'Email and recovery',
        'Keep your original sign-in email. Add and verify another address for contact and password recovery.',
        Icons.mail_outline,
      ),
      if (addresses == null)
        const Notice(
          'Saved email addresses could not be confirmed. Refresh before managing existing addresses.',
          error: true,
        )
      else
        for (final address in addresses)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  address['email']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
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
                        Builder(
                          builder: (context) {
                            final key = _addressCooldownKey('prefer', address);
                            final cooldown = _addressCooldowns[key];
                            final active = cooldown?.active == true;
                            return TextButton(
                              onPressed:
                                  busy ||
                                      active ||
                                      !_canChangeAddress('prefer', address)
                                  ? null
                                  : () => _action('prefer', address),
                              child: Text(
                                active
                                    ? 'Try again in ${cooldown!.remainingSeconds}s'
                                    : 'Use for contact',
                              ),
                            );
                          },
                        ),
                      if (address['is_original'] != true)
                        Builder(
                          builder: (context) {
                            final key = _addressCooldownKey('remove', address);
                            final cooldown = _addressCooldowns[key];
                            final active = cooldown?.active == true;
                            return TextButton(
                              onPressed:
                                  busy ||
                                      active ||
                                      !_canChangeAddress('remove', address)
                                  ? null
                                  : () => _action('remove', address),
                              child: Text(
                                active
                                    ? 'Try again in ${cooldown!.remainingSeconds}s'
                                    : 'Remove email',
                              ),
                            );
                          },
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
          check: (value) =>
              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)
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
              ? _verifyCooldown.active
                    ? 'Verify in ${_verifyCooldown.remainingSeconds}s'
                    : 'Verify and add email'
              : _cooldown > 0
              ? 'Send code in ${_cooldown}s'
              : 'Send verification code',
          busy: busy,
          onPressed: !_sent && _cooldown > 0 || _sent && _verifyCooldown.active
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
}
