import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/widgets.dart';
import '../checkout/location_picker.dart';
import 'auth_shell.dart';
import 'google_auth_contract.dart';
import 'policy_page.dart';

class GoogleRegistrationForm extends StatefulWidget {
  const GoogleRegistrationForm({
    super.key,
    required this.repository,
    required this.contract,
    required this.errors,
    required this.disabled,
    required this.canSubmit,
    required this.busy,
    required this.onSubmit,
    required this.onEdit,
  });
  final BuyerRepository repository;
  final GoogleRegistrationContract contract;
  final Map<String, String> errors;
  final bool disabled, canSubmit, busy;
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  final ValueChanged<String> onEdit;
  @override
  State<GoogleRegistrationForm> createState() => _GoogleRegistrationFormState();
}

class _GoogleRegistrationFormState extends State<GoogleRegistrationForm> {
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
  String? _sex;
  bool _accepted = false,
      _policyError = false,
      _address = false,
      _loadingLocations = false;
  Map<String, String> _location = {
    'region': '',
    'province': '',
    'city': '',
    'barangay': '',
  };

  @override
  void didUpdateWidget(GoogleRegistrationForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contract.policies['terms_version'] !=
            widget.contract.policies['terms_version'] ||
        oldWidget.contract.policies['privacy_version'] !=
            widget.contract.policies['privacy_version']) {
      _accepted = false;
      _policyError = true;
    }
  }

  Future<void> _birthday() async {
    if (widget.disabled) return;
    final maximum = widget.contract.adultMaximum;
    if (maximum.isBefore(DateTime(1900))) return;
    final chosen = DateTime.tryParse(_fields['birthday']!.text);
    final initial =
        chosen != null &&
            !chosen.isBefore(DateTime(1900)) &&
            !chosen.isAfter(maximum)
        ? chosen
        : maximum;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: maximum,
      helpText: 'You must be at least 18 years old',
    );
    if (selected != null && mounted) {
      setState(
        () => _fields['birthday']!.text =
            '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}',
      );
      widget.onEdit('birthday');
    }
  }

  Future<void> _submit() async {
    if (!widget.canSubmit || widget.disabled || _address && _loadingLocations) {
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (widget.contract.policies['required'] == true && !_accepted) {
      setState(() => _policyError = true);
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.onSubmit({
      for (final entry in _fields.entries)
        if (_address || !['address', 'postal_code'].contains(entry.key))
          entry.key: entry.value.text.trim(),
      'sex': _sex,
      'policy_accepted': _accepted,
      if (_address) ..._location,
    });
  }

  void _policy(String key) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PolicyPage(
          repository: widget.repository,
          path: widget.contract.policies[key] as String,
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
    Iterable<String>? autofill,
  }) => AuthField(
    key: ValueKey('google-$key'),
    label: label,
    controller: _fields[key]!,
    enabled: !widget.disabled,
    validator: validator,
    keyboardType: keyboard,
    autofillHints: autofill,
    error: widget.errors[key],
    onChanged: (_) => widget.onEdit(key),
  );

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Google-verified email',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        SelectableText(
          widget.contract.email,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Complete your Bagoo buyer details. Your sign-in email stays with this verified identity.',
          style: TextStyle(color: BagooTheme.muted, height: 1.6),
        ),
        const SizedBox(height: 24),
        _field(
          'first_name',
          'First name',
          autofill: const [AutofillHints.givenName],
          validator: (v) =>
              (v?.trim().length ?? 0) < 2 || (v?.trim().length ?? 0) > 50
              ? 'Use 2–50 characters for your first name.'
              : null,
        ),
        _field('middle_initial', 'Middle initial (optional)'),
        _field(
          'last_name',
          'Last name',
          autofill: const [AutofillHints.familyName],
          validator: (v) =>
              (v?.trim().length ?? 0) < 2 || (v?.trim().length ?? 0) > 50
              ? 'Use 2–50 characters for your last name.'
              : null,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('google-sex'),
            initialValue: _sex,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Sex',
              errorText: widget.errors['sex'],
            ),
            items: [
              'Female',
              'Male',
              'Other',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: widget.disabled
                ? null
                : (v) {
                    setState(() => _sex = v);
                    widget.onEdit('sex');
                  },
            validator: (v) => v == null ? 'Select your sex.' : null,
          ),
        ),
        AuthField(
          key: const ValueKey('google-birthday'),
          label: 'Birth date',
          controller: _fields['birthday']!,
          enabled: !widget.disabled,
          readOnly: true,
          onTap: _birthday,
          hint: 'YYYY-MM-DD',
          icon: Icons.calendar_today_outlined,
          error: widget.errors['birthday'],
          validator: (v) => (v?.isEmpty ?? true)
              ? 'Choose your birth date. You must be 18 or older.'
              : null,
        ),
        _field(
          'phone',
          'Mobile number (optional)',
          keyboard: TextInputType.phone,
          autofill: const [AutofillHints.telephoneNumber],
          validator: (v) =>
              (v?.length ?? 0) > 24 ? 'Use at most 24 characters.' : null,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Add my address now'),
          value: _address,
          onChanged: widget.disabled
              ? null
              : (v) => setState(() => _address = v),
        ),
        if (_address) ...[
          LocationPicker(
            repository: widget.repository,
            initial: _location,
            disabled: widget.disabled,
            onChanged: (v) {
              if (!mounted) return;
              final changed = v.keys
                  .where((key) => v[key] != _location[key])
                  .toList();
              setState(() => _location = v);
              for (final key in changed) {
                widget.onEdit(key);
                if (key == 'city') {
                  widget.onEdit('municipality');
                }
              }
            },
            onLoading: (v) {
              if (mounted) setState(() => _loadingLocations = v);
            },
          ),
          for (final key in [
            'region',
            'province',
            'city',
            'municipality',
            'barangay',
          ])
            if (widget.errors[key] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.errors[key]!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          _field(
            'address',
            'Street / house / unit',
            validator: (v) =>
                (v?.trim().length ?? 0) < 5 || (v?.trim().length ?? 0) > 500
                ? 'Enter a complete street address (5–500 characters).'
                : null,
          ),
          _field(
            'postal_code',
            'Postal code',
            keyboard: TextInputType.number,
            validator: (v) => RegExp(r'^[0-9]{4}$').hasMatch(v?.trim() ?? '')
                ? null
                : 'Enter a four-digit postal code.',
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Buyer identity approval is still required before checkout. You can submit permitted evidence later in Profile.',
          style: TextStyle(color: BagooTheme.muted, height: 1.6),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const ValueKey('google-policies'),
          value: _accepted,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I agree to the Terms of Use and acknowledge the Privacy Notice.',
          ),
          onChanged: widget.disabled
              ? null
              : (v) {
                  setState(() {
                    _accepted = v ?? false;
                    _policyError = false;
                  });
                  widget.onEdit('policy_accepted');
                },
        ),
        if (_policyError || widget.errors['policy_accepted'] != null)
          Semantics(
            liveRegion: true,
            child: Text(
              widget.errors['policy_accepted'] ??
                  'Review and accept the current Terms and Privacy Notice.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: widget.disabled ? null : () => _policy('terms_url'),
              child: const Text('Terms of Use'),
            ),
            TextButton(
              onPressed: widget.disabled ? null : () => _policy('privacy_url'),
              child: const Text('Privacy Notice'),
            ),
          ],
        ),
        if (widget.errors['terms_version'] != null ||
            widget.errors['privacy_version'] != null)
          Text(
            widget.errors['terms_version'] ?? widget.errors['privacy_version']!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        SubmitButton(
          key: const ValueKey('google-create-account'),
          label: 'Create buyer account',
          busy: widget.busy,
          onPressed:
              widget.canSubmit &&
                  !widget.disabled &&
                  !(_address && _loadingLocations)
              ? _submit
              : null,
        ),
      ],
    ),
  );

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }
}
