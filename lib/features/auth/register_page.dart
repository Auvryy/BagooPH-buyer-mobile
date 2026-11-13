import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/retry_cooldown.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/uploads.dart';
import '../../core/file_selection.dart';
import '../checkout/location_picker.dart';
import 'auth_shell.dart';
import 'policy_page.dart';
import 'registration_policy_contract.dart';
import 'verification_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.repository,
    required this.onBack,
    required this.onBrowse,
    required this.onComplete,
    this.selectDocument = pickUpload,
  });
  final BuyerRepository repository;
  final VoidCallback onBack;
  final VoidCallback onBrowse;
  final ValueChanged<WebPage> onComplete;
  final Future<UploadPart?> Function(String) selectDocument;
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _summary = GlobalKey();
  final _fields = {
    for (final key in [
      'first_name',
      'middle_initial',
      'last_name',
      'email',
      'password',
      'password_confirmation',
      'birthday',
      'phone',
      'address',
      'postal_code',
      'delivery_latitude',
      'delivery_longitude',
    ])
      key: TextEditingController(),
  };
  Map<String, dynamic>? _contract;
  Map<String, String> _errors = {};
  String? _error;
  String? _sex;
  bool _accepted = false;
  bool _busy = false;
  int _step = 1;
  String? _verifiedToken;
  UploadPart? _document;
  bool _addAddress = false, _locationLoading = false, _checkingEmail = false;
  Map<String, String> _location = {
    'region': '',
    'province': '',
    'city': '',
    'barangay': '',
  };
  Timer? _emailTimer;
  late final RetryCooldown _codeCooldown, _emailCheckCooldown;
  late final RetryCooldown _registrationCooldown;
  int _emailGeneration = 0;
  String? _emailStatus;
  bool _emailCheckLimited = false;
  Map<String, String>? get _policies => checkedBuyerRegistrationPolicies(
    _contract?['policies'],
    widget.repository.session,
  );

  @override
  void initState() {
    super.initState();
    void changed() {
      if (mounted) setState(() {});
    }

    _codeCooldown = RetryCooldown(changed);
    _emailCheckCooldown = RetryCooldown(changed);
    _registrationCooldown = RetryCooldown(changed);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.registration();
      if (mounted && page.user?['role'] == 'buyer') {
        widget.onComplete(page);
        return;
      }
      if (mounted) {
        setState(() => _contract = page.props);
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Map<String, dynamic> get _values => {
    for (final entry in _fields.entries)
      if ((_addAddress ||
              ![
                'address',
                'postal_code',
                'delivery_latitude',
                'delivery_longitude',
              ].contains(entry.key)) &&
          (!['delivery_latitude', 'delivery_longitude'].contains(entry.key) ||
              entry.value.text.trim().isNotEmpty))
        entry.key: entry.key.startsWith('password')
            ? entry.value.text
            : entry.value.text.trim(),
    'sex': _sex,
    'policy_accepted': _accepted,
    'terms_version': _policies?['terms_version'],
    'privacy_version': _policies?['privacy_version'],
    if (_addAddress) ..._location,
  };

  void _emailChanged() {
    _emailTimer?.cancel();
    final generation = ++_emailGeneration;
    final limited = _emailCheckCooldown.active;
    setState(() {
      _emailStatus = limited ? 'Email availability checks are paused.' : null;
      _emailCheckLimited = limited;
      _checkingEmail = false;
    });
    final email = _fields['email']!.text.trim().toLowerCase();
    if (emailValidator(email) != null || limited) return;
    _emailTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      if (_emailCheckCooldown.active) return;
      setState(() => _checkingEmail = true);
      try {
        final available = await widget.repository.registrationEmailAvailable(
          email,
        );
        if (mounted && generation == _emailGeneration) {
          setState(() {
            _emailStatus = available
                ? 'Email is available for a buyer account.'
                : 'This email already has a buyer account. Log in or recover your password.';
            if (!available) _errors['email'] = _emailStatus!;
          });
        }
      } on BackendException catch (e) {
        if (mounted && e.status == 429) {
          _emailCheckLimited = true;
          _emailCheckCooldown.start(e.data, retryAt: e.retryAt);
        }
        if (mounted && generation == _emailGeneration) {
          setState(() => _emailStatus = e.message);
        }
      } finally {
        if (mounted && generation == _emailGeneration) {
          setState(() => _checkingEmail = false);
        }
      }
    });
  }

  Future<void> _pickDocument() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await widget.selectDocument('id_document');
      if (mounted && file != null) setState(() => _document = file);
    } on BackendException catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(BackendException e) {
    setState(() {
      _error = e.fields.isEmpty
          ? e.message
          : e.fields.values.toSet().join('\n');
      _errors = e.fields;
      if (e.fields.keys.any(
        (key) => [
          'first_name',
          'middle_initial',
          'last_name',
          'email',
          'password',
          'password_confirmation',
          'sex',
        ].contains(key),
      )) {
        _step = 1;
      }
      if (e.fields.containsKey('otp_token')) {
        _verifiedToken = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_summary.currentContext != null) {
        Scrollable.ensureVisible(_summary.currentContext!);
      }
    });
  }

  Future<void> _submit() async {
    if (_busy ||
        (_step == 2 && _verifiedToken == null && _codeCooldown.active) ||
        _registrationCooldown.active ||
        (_step == 2 && _addAddress && _locationLoading)) {
      return;
    }
    if (_policies == null) {
      setState(
        () => _error = 'Account policy details could not be confirmed. Reload registration before continuing.',
      );
      return;
    }
    setState(() {
      _errors = {};
      _error = null;
    });
    if (!_form.currentState!.validate()) {
      return;
    }
    if (_step == 2 && !_accepted) {
      setState(
        () => _error = 'Please agree to the Terms of Use and acknowledge the Privacy Notice.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      if (_step == 1) {
        await widget.repository.validateRegistration(_values, step: 1);
        if (mounted) {
          setState(() => _step = 2);
        }
      } else {
        await widget.repository.validateRegistration(
          _values,
          files: _document == null ? null : [_document!],
        );
        if (!mounted) {
          return;
        }
        if (_verifiedToken == null) {
          late final Map<String, dynamic> sent;
          try {
            sent = await widget.repository.sendCode(
              _fields['email']!.text,
              'registration',
            );
          } on BackendException catch (error) {
            if (mounted && error.status == 429) {
              _codeCooldown.start(error.data, retryAt: error.retryAt);
            }
            rethrow;
          }
          if (!mounted) {
            return;
          }
          _codeCooldown.start(sent);
          final token = await verifyEmailCode(
            context,
            widget.repository,
            _fields['email']!.text,
            'registration',
            sent,
          );
          if (!mounted || token == null) {
            return;
          }
          _verifiedToken = token;
        }
        final page = await widget.repository.register(
          _values,
          _verifiedToken!,
          files: _document == null ? null : [_document!],
        );
        if (mounted) {
          widget.onComplete(page);
        }
      }
    } on BackendException catch (e) {
      if (mounted) {
        if (e.status == 429 &&
            !(_verifiedToken == null && _codeCooldown.active)) {
          _registrationCooldown.start(e.data, retryAt: e.retryAt);
        }
        _showError(e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickBirthday() async {
    final limits = mapOf(_contract?['birthDateLimits']);
    final maximum = strictDateOnly(limits['adult_maximum']);
    if (maximum == null) {
      return;
    }
    final selected = await showDatePicker(
      context: context,
      initialDate: strictDateOnly(_fields['birthday']!.text) ?? maximum,
      firstDate: DateTime(1900),
      lastDate: maximum,
      helpText: 'You must be at least 18 years old',
    );
    if (selected != null && mounted) {
      setState(() {
        _fields['birthday']!.text =
            '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
        _errors.remove('birthday');
      });
    }
  }

  void _policy(String key) {
    final path = _policies?[key];
    if (path is String) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PolicyPage(repository: widget.repository, path: path),
        ),
      );
    }
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    bool password = false,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    Iterable<String>? autofill,
    int? maxLength,
  }) => AuthField(
    key: ValueKey(key),
    label: label,
    controller: _fields[key]!,
    enabled: !_busy,
    hint: hint,
    password: password,
    keyboardType: keyboard,
    autofillHints: autofill,
    maxLength: maxLength,
    validator: validator,
    error: _errors[key],
    onChanged: (_) {
      setState(() {
        _errors.remove(key);
        if (['email', 'password', 'password_confirmation'].contains(key)) {
          _verifiedToken = null;
        }
      });
      if (key == 'email') _emailChanged();
    },
  );
  @override
  void dispose() {
    _emailTimer?.cancel();
    _codeCooldown.dispose();
    _emailCheckCooldown.dispose();
    _registrationCooldown.dispose();
    _emailGeneration++;
    _document = null;
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthShell(
    title: 'Create an Account',
    subtitle: 'Join BagooPH to shop local in two quick steps.',
    registration: true,
    onBack: widget.onBack,
    onBrowse: widget.onBrowse,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            key: _summary,
            padding: const EdgeInsets.only(bottom: 20),
            child: Notice(_error!, error: true),
          ),
        if (_contract != null && _policies == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Notice(
              'Account policy links could not be confirmed. Reload registration before creating an account.',
              error: true,
            ),
          ),
        if (_contract == null) ...[
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ] else ...[
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _StepLabel(
                number: 1,
                title: 'Account details',
                selected: _step == 1,
                complete: _step > 1,
              ),
              _StepLabel(
                number: 2,
                title: 'Personal details',
                selected: _step == 2,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_step == 1) ...[
                  _field(
                    'first_name',
                    'First name',
                    maxLength: 50,
                    autofill: const [AutofillHints.givenName],
                    validator: (v) =>
                        registrationNameValidator(v, label: 'first name'),
                  ),
                  _field(
                    'middle_initial',
                    'Middle initial (optional)',
                    hint: 'e.g. D.',
                    maxLength: 3,
                    validator: registrationMiddleInitialValidator,
                  ),
                  _field(
                    'last_name',
                    'Last name',
                    maxLength: 50,
                    autofill: const [AutofillHints.familyName],
                    validator: (v) =>
                        registrationNameValidator(v, label: 'last name'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: DropdownButtonFormField<String>(
                      initialValue: _sex,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Sex',
                        errorText: _errors['sex'],
                      ),
                      items: ['Female', 'Male', 'Other']
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (s) => setState(() {
                              _sex = s;
                              _errors.remove('sex');
                            }),
                      validator: (s) => s == null ? 'Select your sex.' : null,
                    ),
                  ),
                  _field(
                    'email',
                    'Email address',
                    hint: 'name@example.com',
                    keyboard: TextInputType.emailAddress,
                    autofill: const [AutofillHints.email],
                    validator: emailValidator,
                    maxLength: 255,
                  ),
                  if (_checkingEmail ||
                      _emailStatus != null ||
                      _emailCheckCooldown.active ||
                      _emailCheckLimited)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _checkingEmail
                              ? 'Checking email availability…'
                              : _emailCheckCooldown.active
                              ? 'Email availability check paused. Try again in ${_emailCheckCooldown.remainingSeconds}s; registration will confirm the address.'
                              : _emailCheckLimited
                              ? 'Email availability could not be checked. Registration will confirm the address.'
                              : _emailStatus!,
                          style: const TextStyle(fontSize: 12, height: 1.7),
                        ),
                      ),
                    ),
                  _field(
                    'password',
                    'Password',
                    password: true,
                    autofill: const [AutofillHints.newPassword],
                    validator: passwordValidator,
                    maxLength: 128,
                  ),
                  _field(
                    'password_confirmation',
                    'Confirm password',
                    password: true,
                    validator: (v) =>
                        v == _fields['password']!.text &&
                            (v?.isNotEmpty ?? false)
                        ? null
                        : 'Passwords do not match.',
                    maxLength: 128,
                  ),
                ] else ...[
                  AuthField(
                    label: 'Birth date',
                    controller: _fields['birthday']!,
                    enabled: !_busy,
                    hint: 'YYYY-MM-DD',
                    readOnly: true,
                    onTap: _pickBirthday,
                    icon: Icons.calendar_today_outlined,
                    error: _errors['birthday'],
                    validator: (v) => v == null || v.isEmpty
                        ? 'Choose your birth date. You must be 18 or older.'
                        : null,
                  ),
                  _field(
                    'phone',
                    'Mobile number (optional)',
                    hint: '09XX XXX XXXX',
                    keyboard: TextInputType.phone,
                    autofill: const [AutofillHints.telephoneNumber],
                    maxLength: 24,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add my address now'),
                    value: _addAddress,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _addAddress = value),
                  ),
                  if (_addAddress) ...[
                    LocationPicker(
                      repository: widget.repository,
                      initial: _location,
                      disabled: _busy,
                      onChanged: (value) {
                        if (mounted) setState(() => _location = value);
                      },
                      onLoading: (value) {
                        if (mounted) setState(() => _locationLoading = value);
                      },
                    ),
                    _field(
                      'address',
                      'Street / house / unit',
                      validator: registrationAddressValidator,
                      maxLength: 500,
                    ),
                    _field(
                      'postal_code',
                      'Postal code',
                      keyboard: TextInputType.number,
                      maxLength: 4,
                      validator: (value) =>
                          RegExp(r'^[0-9]{4}$').hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Enter a four-digit postal code.',
                    ),
                    _field(
                      'delivery_latitude',
                      'Delivery latitude (optional)',
                      keyboard: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      maxLength: 20,
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return null;
                        final parsed = double.tryParse(text);
                        return parsed != null && parsed >= -90 && parsed <= 90
                            ? null
                            : 'Enter a latitude between -90 and 90.';
                      },
                    ),
                    _field(
                      'delivery_longitude',
                      'Delivery longitude (optional)',
                      keyboard: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      maxLength: 20,
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return null;
                        final parsed = double.tryParse(text);
                        return parsed != null && parsed >= -180 && parsed <= 180
                            ? null
                            : 'Enter a longitude between -180 and 180.';
                      },
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickDocument,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Choose government ID (optional)'),
                  ),
                  if (_document != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_document!.name),
                      trailing: IconButton(
                        tooltip: 'Remove selected ID',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _document = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  const Text(
                    'JPG, PNG, WEBP or PDF, up to 5 MB. A document is reviewed by Bagoo before checkout access is granted.',
                    style: TextStyle(fontSize: 12, height: 1.7),
                  ),
                  const Text(
                    'Delivery details are collected at checkout. Identity approval is required before purchasing.',
                    style: TextStyle(
                      fontSize: 13,
                      color: BagooTheme.muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  CheckboxListTile(
                    value: _accepted,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: _busy || _policies == null
                        ? null
                        : (v) => setState(() => _accepted = v ?? false),
                    title: const Text(
                      'I agree to the Terms of Use and acknowledge the Privacy Notice.',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: _policies == null
                            ? null
                            : () => _policy('terms_url'),
                        child: const Text('Terms of Use'),
                      ),
                      TextButton(
                        onPressed: _policies == null
                            ? null
                            : () => _policy('privacy_url'),
                        child: const Text('Privacy Notice'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                SubmitButton(
                  label: _registrationCooldown.active
                      ? 'Try again in ${_registrationCooldown.remainingSeconds}s'
                      : _step == 1
                      ? 'Continue'
                      : _verifiedToken == null && _codeCooldown.active
                      ? 'Send code in ${_codeCooldown.remainingSeconds}s'
                      : 'Verify email & create account',
                  busy: _busy,
                  onPressed:
                      _policies == null ||
                          _registrationCooldown.active ||
                          (_step == 2 &&
                              _verifiedToken == null &&
                              _codeCooldown.active)
                      ? null
                      : _submit,
                ),
                if (_step == 2)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _step = 1),
                    child: const Text('Back to account details'),
                  ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({
    required this.number,
    required this.title,
    required this.selected,
    this.complete = false,
  });
  final int number;
  final String title;
  final bool selected;
  final bool complete;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        radius: 14,
        backgroundColor: selected || complete
            ? BagooTheme.crimson
            : BagooTheme.canvas,
        child: complete
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : Text(
                '$number',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : BagooTheme.muted,
                ),
              ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? BagooTheme.ink : BagooTheme.muted,
          ),
        ),
      ),
    ],
  );
}
