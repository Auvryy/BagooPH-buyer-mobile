import 'package:flutter/material.dart';

import '../../core/web_session.dart';
import '../../core/uploads.dart';
import '../../core/widgets.dart';
import '../products/product_widgets.dart';
import 'profile_widgets.dart';
import 'profile_repository.dart';

class IdentitySection extends StatefulWidget {
  const IdentitySection({
    super.key,
    required this.repository,
    required this.page,
    required this.onChanged,
    required this.reload,
  });
  final ProfileRepository repository;
  final WebPage page;
  final ValueChanged<WebPage> onChanged;
  final Future<void> Function() reload;
  @override
  State<IdentitySection> createState() => _IdentitySectionState();
}

class _IdentitySectionState extends ProfileFormState<IdentitySection> {
  final _value = TextEditingController(), _reason = TextEditingController();
  final _files = <String, UploadPart>{};
  String _field = 'birthday';
  bool _conflict = false;
  Map<String, dynamic> get user => mapOf(widget.page.props['user']);
  Map<String, dynamic> get subject =>
      mapOf(mapOf(widget.page.props['identityCorrection'])['subject']);
  List<Map<String, dynamic>> get choices => mapsOf(subject['fields']);
  Map<String, dynamic> get selected =>
      choices.where((f) => f['key'] == _field).firstOrNull ??
      {'key': 'birthday', 'label': 'Birth date', 'type': 'date', 'options': []};
  @override
  void initState() {
    super.initState();
    _resetValue();
  }

  void _resetValue() {
    _value.text = mapOf(subject['values'])[_field]?.toString() ?? '';
  }

  @override
  void didUpdateWidget(IdentitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = mapOf(
      mapOf(oldWidget.page.props['identityCorrection'])['subject'],
    )['source_token'];
    if (previous != subject['source_token']) {
      _resetValue();
      _files.clear();
      _conflict = false;
      success = 'Recorded identity details changed. Review the current values before requesting a correction.';
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(String key) async => perform(() async {
    final file = await pickUpload(key);
    if (file != null && mounted) setState(() => _files[key] = file);
    return null;
  }, validate: false);
  void _view(String url, String title) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PrivateDocumentPage(
        repository: widget.repository,
        path: url,
        title: title,
      ),
    ),
  );
  Future<void> _date() async {
    final now = DateTime.now();
    final initial =
        DateTime.tryParse(_value.text) ??
        DateTime(now.year - 20, now.month, now.day);
    final result = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(1900)) || initial.isAfter(now)
          ? now
          : initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (result != null && mounted) {
      setState(() => _value.text = result.toIso8601String().split('T').first);
    }
  }

  Future<void> _submit() async {
    await perform(() async {
      try {
        final result = await widget.repository.json(
          '/account/identity-corrections',
          {
            'source_token': subject['source_token'],
            'shop_id': subject['shop_id'],
            'changes': {_field: _value.text.trim()},
            'reason': _reason.text.trim(),
          },
          files: _files.values.toList(),
        );
        if (result['id'] is! num) {
          throw const BackendException(
            'The correction request was not confirmed.',
          );
        }
      } on BackendException catch (e) {
        if (mounted && e.status == 409) setState(() => _conflict = true);
        rethrow;
      }
      if (mounted) {
        _files.clear();
        _reason.clear();
      }
      await widget.reload();
      return 'Correction requested. Your recorded identity stays unchanged until review.';
    });
  }

  @override
  Widget build(BuildContext context) => content([
    const ProfileHeading(
      'Identity correction',
      'Review your verification and request changes to reviewed identity details. Corrections need supporting evidence and admin approval.',
      Icons.fingerprint,
    ),
    Text(
      identityLabel(user),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
    const SizedBox(height: 12),
    Notice(
      reviewed(user)
          ? 'Your identity review is approved. Other account restrictions still apply.'
          : user['kyc_status'] == 'pending_approval'
          ? 'Your identity documents are awaiting review. You can continue browsing while the review is pending.'
          : user['kyc_status'] == 'rejected'
          ? user['kyc_feedback']?.toString() ??
                'Submit a clear, valid government photo ID for another review.'
          : 'Upload a valid government photo ID to request identity verification.',
    ),
    if (user['id_document_path'] is String)
      TextButton.icon(
        onPressed: busy
            ? null
            : () => _view(user['id_document_path'], 'Identity document'),
        icon: const Icon(Icons.description_outlined),
        label: const Text('View document on file'),
      ),
    const SizedBox(height: 24),
    if (mapOf(
          mapOf(widget.page.props['buyerApplication'])['application'],
        )['can_correct'] ==
        true)
      OutlinedButton.icon(
        onPressed: busy
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ApplicationEditor(
                    repository: widget.repository,
                    page: widget.page,
                    onSaved: widget.onChanged,
                  ),
                ),
              ),
        icon: const Icon(Icons.edit_note),
        label: const Text('Update application details'),
      ),
    if (!reviewed(user) && user['kyc_status'] != 'pending_approval') ...[
      OutlinedButton.icon(
        onPressed: busy ? null : () => _pick('id_document'),
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Choose government ID'),
      ),
      if (_files['id_document'] != null) ...[
        Text(_files['id_document']!.name, style: const TextStyle(height: 1.7)),
        SubmitButton(
          label: 'Submit ID for Verification',
          busy: busy,
          onPressed: () => perform(() async {
            final result = await widget.repository.mutate(
              '/buyer/kyc/upload',
              {},
              files: [_files['id_document']!],
            );
            if (mounted) {
              _files.clear();
              widget.onChanged(result);
            }
            return 'Your document was submitted for review.';
          }, validate: false),
        ),
      ],
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'JPG, PNG, WEBP or PDF, up to 5 MB.',
          style: TextStyle(fontSize: 12),
        ),
      ),
    ],
    if (subject.isNotEmpty) ...[
      const Divider(height: 40),
      const ProfileHeading(
        'Request a correction',
        'Choose one reviewed detail and enter the corrected value. Account role and separate restrictions stay in place.',
        Icons.edit_note,
      ),
      DropdownButtonFormField<String>(
        initialValue: _field,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Detail to correct'),
        items: [
          for (final choice in choices)
            DropdownMenuItem(
              value: choice['key'].toString(),
              child: Text(
                choice['label'].toString(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (!choices.any((f) => f['key'] == 'birthday'))
            const DropdownMenuItem(
              value: 'birthday',
              child: Text('Birth date'),
            ),
        ],
        onChanged: busy || _conflict
            ? null
            : (v) => setState(() {
                _field = v!;
                _resetValue();
              }),
      ),
      const SizedBox(height: 20),
      if (selected['type'] == 'date')
        OutlinedButton.icon(
          onPressed: busy || _conflict ? null : _date,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            'Corrected birth date: ${_value.text.isEmpty ? 'Choose date' : _value.text}',
          ),
        )
      else if (selected['options'] is List &&
          (selected['options'] as List).isNotEmpty)
        DropdownButtonFormField<String>(
          key: ValueKey(_field),
          initialValue: (selected['options'] as List).contains(_value.text)
              ? _value.text
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Corrected ${selected['label']}',
          ),
          items: [
            for (final option in selected['options'])
              DropdownMenuItem(
                value: option.toString(),
                child: Text(option.toString()),
              ),
          ],
          onChanged: busy || _conflict
              ? null
              : (v) => setState(() => _value.text = v ?? ''),
          validator: (v) => v == null ? 'Choose a value.' : null,
        )
      else
        field(
          'changes.$_field',
          'Corrected ${selected['label']}',
          _value,
          enabled: !_conflict,
          max: 100,
        ),
      const SizedBox(height: 12),
      Text(
        'Currently recorded: ${mapOf(subject['values'])[_field] ?? 'Not recorded'}',
        style: const TextStyle(fontSize: 12, height: 1.7),
      ),
      const SizedBox(height: 20),
      field(
        'reason',
        'Reason',
        _reason,
        min: 5,
        max: 1000,
        lines: 3,
        enabled: !_conflict,
      ),
      for (final kind in (subject['required_documents'] as List? ?? [])) ...[
        OutlinedButton.icon(
          onPressed: busy || _conflict
              ? null
              : () => _pick(
                  {
                        'id': 'id_document',
                        'permit': 'business_permit',
                        'license': 'driver_license',
                        'orcr': 'or_cr_document',
                        'franchise': 'franchise_document',
                      }[kind] ??
                      'id_document',
                ),
          icon: const Icon(Icons.upload_file_outlined),
          label: Text('Choose $kind evidence'),
        ),
      ],
      for (final file in _files.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(file.name),
          subtitle: const Text('Replacement evidence selected'),
          trailing: IconButton(
            tooltip: 'Remove selected evidence',
            onPressed: busy
                ? null
                : () => setState(() => _files.remove(file.field)),
            icon: const Icon(Icons.close),
          ),
        ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Replacement evidence: JPG, PNG, WEBP or PDF, up to 5 MB per file. Earlier reviewed files are retained.',
          style: TextStyle(fontSize: 12, height: 1.7),
        ),
      ),
      if (_conflict)
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  await widget.reload();
                  if (mounted) {
                    setState(() {
                      _conflict = false;
                      _resetValue();
                    });
                  }
                },
          child: const Text('Reload current identity details'),
        ),
      SubmitButton(
        label: 'Submit correction request',
        busy: busy,
        onPressed: _conflict ? null : _submit,
      ),
      const Divider(height: 40),
      const ProfileHeading('Requests and decisions', '', Icons.history),
      if (mapsOf(subject['requests']).isEmpty)
        const Text('No correction requests have been recorded.'),
      for (final request in mapsOf(subject['requests']))
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request #${request['id']} · ${mapOf(request['decision'])['action'] == 'approve'
                    ? 'Approved'
                    : mapOf(request['decision'])['action'] == 'reject'
                    ? 'Rejected'
                    : request['current'] == true
                    ? 'Awaiting review'
                    : 'A new request is required'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                readableDateTime(request['requested_at']),
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
              Text(
                request['reason']?.toString() ?? '',
                style: const TextStyle(height: 1.7),
              ),
              for (final change in mapOf(request['proposed']).entries)
                Text(
                  '${change.key.replaceAll('_', ' ')}: ${mapOf(request['before'])[change.key] ?? 'Not recorded'} → ${change.value}',
                  style: const TextStyle(height: 1.7),
                ),
              for (final doc in mapOf(request['documents']).entries)
                if (doc.value is String)
                  TextButton(
                    onPressed: () => _view(doc.value, '${doc.key} evidence'),
                    child: Text('View ${doc.key} evidence'),
                  ),
              if (request['decision'] != null)
                Text(
                  '${mapOf(request['decision'])['reason']}\n${mapOf(request['decision'])['actor']} · ${readableDateTime(mapOf(request['decision'])['decided_at'])}',
                  style: const TextStyle(height: 1.7),
                ),
            ],
          ),
        ),
    ],
  ]);
}

class _ApplicationEditor extends StatefulWidget {
  const _ApplicationEditor({
    required this.repository,
    required this.page,
    required this.onSaved,
  });
  final ProfileRepository repository;
  final WebPage page;
  final ValueChanged<WebPage> onSaved;
  @override
  State<_ApplicationEditor> createState() => _ApplicationEditorState();
}

class _ApplicationEditorState extends ProfileFormState<_ApplicationEditor> {
  late final Map<String, TextEditingController> _values;
  UploadPart? _document;
  Map<String, dynamic> get data => mapOf(widget.page.props['buyerApplication']);
  Map<String, dynamic> get application => mapOf(data['application']);
  List<Map<String, dynamic>> get inputs => mapsOf(application['fields'])
      .where(
        (f) => [
          'first_name',
          'middle_name',
          'last_name',
          'name',
          'phone',
          'sex',
          'address',
          'city',
          'postal_code',
        ].contains(f['key']),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    _values = {
      for (final input in inputs)
        input['key'].toString(): TextEditingController(
          text: mapOf(application['values'])[input['key']]?.toString() ?? '',
        ),
      'birthday': TextEditingController(
        text:
            mapOf(
              application['values'],
            )['birthday']?.toString().split('T').first ??
            '',
      ),
    };
  }

  @override
  void dispose() {
    for (final value in _values.values) {
      value.dispose();
    }
    super.dispose();
  }

  Future<void> _date() async {
    final last = DateTime.tryParse(
      mapOf(data['birth_date_limits'])['adult_maximum']?.toString() ?? '',
    );
    if (last == null) {
      setState(
        () => problem =
            'Birth-date requirements are unavailable. Reload your profile.',
      );
      return;
    }
    final current = DateTime.tryParse(_values['birthday']!.text);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current != null &&
              !current.isAfter(last) &&
              current.isAfter(DateTime(1900))
          ? current
          : last,
      firstDate: DateTime(1900),
      lastDate: last,
    );
    if (picked != null && mounted) {
      setState(
        () => _values['birthday']!.text = picked
            .toIso8601String()
            .split('T')
            .first,
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Buyer application')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: content([
              const ProfileHeading(
                'Application details',
                'Name parts must match your identity document. Changes need a fresh admin review. Your original sign-in email and account role stay the same.',
                Icons.badge_outlined,
              ),
              if (mapOf(data['user'])['kyc_feedback'] != null)
                Notice(mapOf(data['user'])['kyc_feedback'].toString()),
              for (final input in inputs)
                if (input['type'] == 'select') ...[
                  DropdownButtonFormField<String>(
                    initialValue:
                        (input['options'] as List? ?? []).contains(
                          _values[input['key']]!.text,
                        )
                        ? _values[input['key']]!.text
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: input['label'].toString(),
                      errorText: errors[input['key']],
                      errorMaxLines: 4,
                    ),
                    items: [
                      for (final option in input['options'] as List? ?? [])
                        DropdownMenuItem(
                          value: option.toString(),
                          child: Text(option.toString()),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(
                            () => _values[input['key']]!.text = value ?? '',
                          ),
                    validator: (value) =>
                        input['required'] == true && value == null
                        ? 'Choose ${input['label']}.'
                        : null,
                  ),
                  const SizedBox(height: 20),
                ] else
                  field(
                    input['key'].toString(),
                    input['label'].toString(),
                    _values[input['key']]!,
                    required: input['required'] == true,
                    min: (input['min_length'] as num?)?.toInt() ?? 1,
                    max: (input['max_length'] as num?)?.toInt() ?? 100,
                    keyboard: input['type'] == 'tel'
                        ? TextInputType.phone
                        : TextInputType.text,
                  ),
              OutlinedButton.icon(
                onPressed: busy ? null : _date,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  'Birth date: ${_values['birthday']!.text.isEmpty ? 'Choose date' : _values['birthday']!.text}',
                ),
              ),
              const SizedBox(height: 20),
              if (data['identity_document_url'] is String)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PrivateDocumentPage(
                              repository: widget.repository,
                              path: data['identity_document_url'],
                              title: 'Identity document on file',
                            ),
                          ),
                        ),
                  child: const Text('View identity document on file'),
                ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => perform(() async {
                        final document = await pickUpload('id_document');
                        if (document != null && mounted) {
                          setState(() => _document = document);
                        }
                        return null;
                      }, validate: false),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Choose replacement government ID'),
              ),
              if (_document != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_document!.name),
                  trailing: IconButton(
                    tooltip: 'Remove selected document',
                    onPressed: busy
                        ? null
                        : () => setState(() => _document = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'JPG, PNG, WEBP or PDF, up to 5 MB. Upload a corrected document or change an application detail.',
                  style: TextStyle(fontSize: 12, height: 1.7),
                ),
              ),
              SubmitButton(
                label: 'Submit application for review',
                busy: busy,
                onPressed: () => perform(() async {
                  final changes = {
                    for (final value in _values.entries)
                      if (value.value.text.trim() !=
                          mapOf(application['values'])[value.key]?.toString())
                        value.key: value.value.text.trim(),
                  };
                  if (changes.isEmpty && _document == null) {
                    throw const BackendException(
                      'Change an application detail or choose a replacement document.',
                    );
                  }
                  final page = await widget.repository.mutate(
                    '/kyc/resubmit',
                    changes,
                    files: _document == null ? null : [_document!],
                  );
                  if (context.mounted) {
                    widget.onSaved(page);
                    Navigator.pop(context);
                  }
                  return null;
                }),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}
