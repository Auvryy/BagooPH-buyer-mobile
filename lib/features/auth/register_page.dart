import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'auth_shell.dart';
import 'policy_page.dart';
import 'verification_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.repository,
    required this.onBack,
    required this.onBrowse,
    required this.onComplete,
  });
  final BuyerRepository repository;
  final VoidCallback onBack;
  final VoidCallback onBrowse;
  final ValueChanged<WebPage> onComplete;
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.registration();
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
      entry.key: entry.key.startsWith('password')
          ? entry.value.text
          : entry.value.text.trim(),
    'sex': _sex,
    'policy_accepted': _accepted,
    'terms_version': mapOf(_contract?['policies'])['terms_version'],
    'privacy_version': mapOf(_contract?['policies'])['privacy_version'],
  };
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
        await widget.repository.validateRegistration(_values);
        if (!mounted) {
          return;
        }
        if (_verifiedToken == null) {
          final sent = await widget.repository.sendCode(
            _fields['email']!.text,
            'registration',
          );
          if (!mounted) {
            return;
          }
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
        final page = await widget.repository.register(_values, _verifiedToken!);
        if (mounted) {
          widget.onComplete(page);
        }
      }
    } on BackendException catch (e) {
      if (mounted) {
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
    final maximum = DateTime.tryParse(
      limits['adult_maximum']?.toString() ?? '',
    );
    if (maximum == null) {
      return;
    }
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_fields['birthday']!.text) ?? maximum,
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
    final path = mapOf(_contract?['policies'])[key];
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
  }) => AuthField(
    key: ValueKey(key),
    label: label,
    controller: _fields[key]!,
    enabled: !_busy,
    hint: hint,
    password: password,
    keyboardType: keyboard,
    autofillHints: autofill,
    validator: validator,
    error: _errors[key],
    onChanged: (_) => setState(() {
      _errors.remove(key);
      if (['email', 'password', 'password_confirmation'].contains(key)) {
        _verifiedToken = null;
      }
    }),
  );
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthShell(
    title: 'Create an Account',
    subtitle: 'Join BagooPH in two quick steps to start shopping local Filipino brands.',
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
                    autofill: const [AutofillHints.givenName],
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? 'Enter your first name.'
                        : null,
                  ),
                  _field(
                    'middle_initial',
                    'Middle initial (optional)',
                    hint: 'e.g. D.',
                  ),
                  _field(
                    'last_name',
                    'Last name',
                    autofill: const [AutofillHints.familyName],
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? 'Enter your last name.'
                        : null,
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
                  ),
                  _field(
                    'password',
                    'Password',
                    password: true,
                    autofill: const [AutofillHints.newPassword],
                    validator: passwordValidator,
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
                    onChanged: _busy
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
                        onPressed: () => _policy('terms_url'),
                        child: const Text('Terms of Use'),
                      ),
                      TextButton(
                        onPressed: () => _policy('privacy_url'),
                        child: const Text('Privacy Notice'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                SubmitButton(
                  label: _step == 1
                      ? 'Continue'
                      : 'Verify email & create account',
                  busy: _busy,
                  onPressed: _submit,
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
