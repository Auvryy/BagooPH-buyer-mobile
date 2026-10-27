import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../checkout/location_picker.dart';
import 'auth_shell.dart';
import 'policy_page.dart';

class GoogleBuyerRegistrationPage extends StatefulWidget {
  const GoogleBuyerRegistrationPage({
    super.key,
    required this.repository,
    required this.challenge,
    required this.onBack,
    required this.onBrowse,
    required this.onComplete,
  });

  final BuyerRepository repository;
  final GoogleRegistrationChallenge challenge;
  final VoidCallback onBack;
  final VoidCallback onBrowse;
  final ValueChanged<WebPage> onComplete;

  @override
  State<GoogleBuyerRegistrationPage> createState() =>
      _GoogleBuyerRegistrationPageState();
}

class _GoogleBuyerRegistrationPageState
    extends State<GoogleBuyerRegistrationPage> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'first_name',
      'middle_initial',
      'last_name',
      'birthday',
      'phone',
      'address',
      'postal_code',
    ])
      key: TextEditingController(),
  };
  final Map<String, String> _location = {
    'region': '',
    'province': '',
    'city': '',
    'barangay': '',
  };
  Map<String, String> _errors = {};
  String? _error;
  String? _sex;
  bool _accepted = false;
  bool _busy = false;
  bool _addressLoading = true;

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final maximum = DateTime.tryParse(
      widget.challenge.birthDateLimits['adult_maximum']?.toString() ?? '',
    );
    if (maximum == null) return;
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

  Widget _field(
    String key,
    String label, {
    bool required = true,
    int? maxLength,
    int minLength = 0,
    TextInputType? keyboardType,
    int maxLines = 1,
    VoidCallback? onTap,
    bool readOnly = false,
  }) => TextFormField(
    controller: _fields[key],
    enabled: !_busy,
    readOnly: readOnly,
    keyboardType: keyboardType,
    maxLength: maxLength,
    maxLines: maxLines,
    onTap: onTap,
    decoration: InputDecoration(
      labelText: label,
      errorText: _errors[key],
      counterText: maxLength == null ? null : '',
      suffixIcon: readOnly ? const Icon(Icons.calendar_today_outlined) : null,
    ),
    validator: (value) {
      final text = value?.trim() ?? '';
      if (required && text.isEmpty) return 'Enter $label.';
      if (text.isNotEmpty && text.length < minLength) {
        return '$label must contain at least $minLength characters.';
      }
      if (key == 'postal_code' &&
          text.isNotEmpty &&
          !RegExp(r'^\d{4}$').hasMatch(text)) {
        return 'Enter a four-digit postal code.';
      }
      return null;
    },
    onChanged: (_) {
      if (_errors.containsKey(key)) setState(() => _errors.remove(key));
    },
  );

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _errors = {};
    });
    if (!_form.currentState!.validate()) return;
    if (_addressLoading && _location.values.any((value) => value.isNotEmpty)) {
      setState(
        () => _error = 'Wait for the location choices to finish loading.',
      );
      return;
    }
    if (!_accepted) {
      setState(
        () => _error = 'Agree to the Terms of Use and acknowledge the Privacy Notice to continue.',
      );
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      final values = <String, dynamic>{
        'registration_nonce': widget.challenge.nonce,
        'policy_accepted': _accepted,
        'terms_version': widget.challenge.policies['terms_version'],
        'privacy_version': widget.challenge.policies['privacy_version'],
        'first_name': _fields['first_name']!.text.trim(),
        'middle_initial': _fields['middle_initial']!.text.trim(),
        'last_name': _fields['last_name']!.text.trim(),
        'birthday': _fields['birthday']!.text,
        'phone': _fields['phone']!.text.trim(),
        'sex': _sex,
        'address': _fields['address']!.text.trim(),
        'postal_code': _fields['postal_code']!.text.trim(),
        ..._location,
        'municipality': _location['city'],
      };
      final page = await widget.repository.completeGoogleRegistration(values);
      if (mounted) widget.onComplete(page);
    } on BackendException catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.fields.isEmpty
              ? exception.message
              : exception.fields.values.toSet().join('\n');
          _errors = exception.fields;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPolicy(String key) {
    final path = widget.challenge.policies[key];
    if (path is! String) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PolicyPage(repository: widget.repository, path: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AuthShell(
    title: 'Finish creating your account',
    subtitle: 'Confirm your details to create your Bagoo buyer account.',
    registration: true,
    onBack: widget.onBack,
    onBrowse: widget.onBrowse,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _googleIdentity(),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Notice(_error!, error: true),
          ],
          const SizedBox(height: 20),
          const Text(
            'Name on your identity document',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _field('first_name', 'First name', minLength: 2, maxLength: 50),
          _field(
            'middle_initial',
            'Middle name or initial (optional)',
            required: false,
            maxLength: 50,
          ),
          _field('last_name', 'Last name', minLength: 2, maxLength: 50),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            decoration: InputDecoration(
              labelText: 'Sex',
              errorText: _errors['sex'],
            ),
            items: const ['Female', 'Male', 'Other']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _sex = value;
                    _errors.remove('sex');
                  }),
            validator: (value) => value == null ? 'Choose an option.' : null,
          ),
          const SizedBox(height: 14),
          _field(
            'birthday',
            'Birth date',
            readOnly: true,
            onTap: _busy ? null : _pickBirthday,
          ),
          _field(
            'phone',
            'Mobile number (optional)',
            required: false,
            maxLength: 24,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 8),
          const Text(
            'Delivery address (optional)',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          LocationPicker(
            repository: widget.repository,
            initial: _location,
            errors: _errors,
            required: false,
            disabled: _busy,
            onLoading: (loading) {
              if (mounted) setState(() => _addressLoading = loading);
            },
            onChanged: (value) {
              if (mounted) {
                setState(() {
                  _location
                    ..clear()
                    ..addAll(value);
                  _errors.removeWhere(
                    (key, _) => [
                      'region',
                      'province',
                      'city',
                      'barangay',
                    ].contains(key),
                  );
                });
              }
            },
          ),
          _field(
            'address',
            'Street / house / unit (optional)',
            required: false,
            maxLength: 500,
            maxLines: 2,
          ),
          _field(
            'postal_code',
            'Postal code (optional)',
            required: false,
            maxLength: 4,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          const Text(
            'You can browse now. Identity approval is still required before placing purchases.',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: BagooTheme.muted,
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _accepted,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _busy
                ? null
                : (value) => setState(() => _accepted = value ?? false),
            title: const Text(
              'I agree to the Terms of Use and acknowledge the Privacy Notice.',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          if (_errors['policy_accepted'] != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                _errors['policy_accepted']!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _openPolicy('terms_url'),
                child: const Text('Terms of Use'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _openPolicy('privacy_url'),
                child: const Text('Privacy Notice'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SubmitButton(
            label: 'Create buyer account',
            busy: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    ),
  );

  Widget _googleIdentity() {
    final name = widget.challenge.identity['name']?.toString().trim() ?? '';
    final email = widget.challenge.identity['email']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BagooTheme.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BagooTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          SelectableText(email, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 6),
          const Text(
            'This will create a buyer account using your verified Google email.',
            style: TextStyle(fontSize: 12, color: BagooTheme.muted),
          ),
        ],
      ),
    );
  }
}
