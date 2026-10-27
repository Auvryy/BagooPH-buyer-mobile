import 'package:flutter/material.dart';

import '../../core/uploads.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

class PersonalSection extends StatefulWidget {
  const PersonalSection({
    super.key,
    required this.repository,
    required this.page,
    required this.onChanged,
    required this.onIdentity,
  });
  final ProfileRepository repository;
  final WebPage page;
  final ValueChanged<WebPage> onChanged;
  final VoidCallback onIdentity;
  @override
  State<PersonalSection> createState() => _PersonalSectionState();
}

class _PersonalSectionState extends ProfileFormState<PersonalSection> {
  late final TextEditingController _phone;
  UploadPart? _avatar;
  bool _remove = false, _dirty = false;
  Map<String, dynamic> get user => mapOf(widget.page.props['user']);
  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: user['phone']?.toString() ?? '');
  }

  @override
  void didUpdateWidget(PersonalSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty) _phone.text = user['phone']?.toString() ?? '';
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pick() => perform(() async {
    final photo = await pickUpload('avatar', avatar: true);
    if (photo != null && mounted) {
      setState(() {
        _avatar = photo;
        _remove = false;
        _dirty = true;
      });
    }
    return null;
  }, validate: false);

  Future<void> _save() => perform(() async {
    final page = await widget.repository.mutate('/buyer/profile', {
      'name': user['name'],
      'phone': _phone.text.trim(),
      'remove_avatar': _remove,
    }, files: _avatar == null ? null : [_avatar!]);
    if (mounted) {
      _dirty = false;
      _avatar = null;
      _remove = false;
      _phone.text = mapOf(page.props['user'])['phone']?.toString() ?? '';
      widget.onChanged(page);
    }
    return 'Profile updated successfully.';
  }).then((_) {});

  Widget _record(String title, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: InputDecorator(
      decoration: InputDecoration(labelText: title, enabled: false),
      child: SelectableText(
        value?.toString().isNotEmpty == true
            ? value.toString()
            : 'Not recorded',
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => content([
    const ProfileHeading(
      'Personal Information',
      'Update your contact information and profile photo.',
      Icons.person_outline,
    ),
    Wrap(
      spacing: 20,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_avatar != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              _avatar!.bytes,
              width: 88,
              height: 88,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, size: 64),
            ),
          )
        else
          ProfileAvatar(
            {...user, if (_remove) 'avatar': null},
            widget.repository.session,
            size: 88,
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : _pick,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Choose profile photo'),
            ),
            if (user['avatar'] != null || _avatar != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _remove = true;
                        _avatar = null;
                        _dirty = true;
                      }),
                child: const Text('Remove photo'),
              ),
          ],
        ),
      ],
    ),
    const SizedBox(height: 12),
    Text(
      _avatar != null || _remove
          ? 'Photo change selected. Save your profile to apply it.'
          : 'JPG, PNG, WEBP or GIF, up to 3 MB.',
      style: const TextStyle(fontSize: 12, height: 1.6),
    ),
    const Divider(height: 40),
    _record('Registered name', user['name']),
    for (final e in {
      'first_name': 'First name',
      'middle_name': 'Middle name',
      'last_name': 'Last name',
    }.entries)
      _record(e.value, user[e.key]),
    _record('Original sign-in email', user['email']),
    Text(
      user['email_verified_at'] == null
          ? 'Email verification is required for account security actions.'
          : 'Your sign-in email is verified.',
      style: const TextStyle(fontSize: 12, height: 1.6),
    ),
    if (user['email_verified_at'] == null)
      TextButton(
        onPressed: busy
            ? null
            : () => perform(() async {
                await widget.repository.mutate(
                  '/email/verification-notification',
                  {},
                  requireMessage: false,
                );
                return 'Verification link requested. Check your sign-in email.';
              }, validate: false),
        child: const Text('Resend verification email'),
      ),
    const SizedBox(height: 20),
    field(
      'phone',
      'Mobile contact',
      _phone,
      required: false,
      max: 20,
      keyboard: TextInputType.phone,
      autofill: const [AutofillHints.telephoneNumber],
      hint: 'Philippine mobile number, such as 09171234567.',
      onChanged: (_) => _dirty = true,
    ),
    _record('Birthday', user['birthday']?.toString().split('T').first),
    _record('Gender', user['sex'] ?? user['gender']),
    TextButton.icon(
      onPressed: busy ? null : widget.onIdentity,
      icon: const Icon(Icons.fingerprint),
      label: Text(
        reviewed(user)
            ? 'Request an identity correction'
            : 'Review identity verification',
      ),
    ),
    const SizedBox(height: 12),
    SubmitButton(
      label: busy ? 'Saving profile…' : 'Save Profile Changes',
      onPressed: _save,
      busy: busy,
    ),
  ]);
}

class PasswordSection extends StatefulWidget {
  const PasswordSection({
    super.key,
    required this.repository,
    required this.page,
    required this.onChanged,
  });
  final ProfileRepository repository;
  final WebPage page;
  final ValueChanged<WebPage> onChanged;
  @override
  State<PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ProfileFormState<PasswordSection> {
  final _current = TextEditingController(),
      _password = TextEditingController(),
      _confirmation = TextEditingController();
  @override
  void dispose() {
    for (final controller in [_current, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => content([
    const ProfileHeading(
      'Account Password & Security',
      'Use a unique password between 8 and 128 characters.',
      Icons.key_outlined,
    ),
    if (mapOf(widget.page.props['user'])['google_id'] != null)
      const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Notice(
          'Your account is connected with Google. Your original sign-in email remains unchanged.',
        ),
      ),
    field(
      'current_password',
      'Current password',
      _current,
      secret: true,
      max: 4096,
      autofill: const [AutofillHints.password],
    ),
    field(
      'password',
      'New password',
      _password,
      secret: true,
      min: 8,
      max: 128,
      autofill: const [AutofillHints.newPassword],
    ),
    field(
      'password_confirmation',
      'Confirm new password',
      _confirmation,
      secret: true,
      max: 128,
      autofill: const [AutofillHints.newPassword],
      check: (value) =>
          value == _password.text ? null : 'The passwords do not match.',
    ),
    SubmitButton(
      label: 'Update password',
      busy: busy,
      onPressed: () => perform(() async {
        final page = await widget.repository.mutate(
          '/password',
          {
            'current_password': _current.text,
            'password': _password.text,
            'password_confirmation': _confirmation.text,
          },
          method: 'PUT',
          requireMessage: false,
        );
        if (mounted) {
          _current.clear();
          _password.clear();
          _confirmation.clear();
          widget.onChanged(page);
        }
        return 'Your password was updated.';
      }),
    ),
  ]);
}
