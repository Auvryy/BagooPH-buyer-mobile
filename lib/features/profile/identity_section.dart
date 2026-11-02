import 'package:flutter/material.dart';

import '../../core/application_text_validation.dart';
import '../../core/form_metadata.dart';
import '../../core/resource_ids.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../../core/buyer_account_scope.dart';
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

class _IdentitySectionState extends BuyerProfileFormState<IdentitySection> {
  @override
  ProfileRepository get accountRepository => widget.repository;
  @override
  WebPage get accountPage => widget.page;
  final _value = TextEditingController(), _reason = TextEditingController();
  final _files = <String, UploadPart>{};
  String _field = 'birthday';
  bool _conflict = false;
  @override
  void clearBuyerDraft() {
    _files.clear();
    _value.clear();
    _reason.clear();
    _conflict = false;
  }

  Map<String, dynamic> get user => mapOf(widget.page.props['user']);
  Map<String, dynamic> get subject =>
      mapOf(mapOf(widget.page.props['identityCorrection'])['subject']);
  List<Map<String, dynamic>> get _choiceRows => mapsOf(subject['fields']);
  List<Map<String, dynamic>>? get _validatedRequests {
    final raw = subject['requests'];
    if (raw is! List) return null;
    final rows = mapsOf(raw);
    final ids = <int>{};
    bool primitiveMap(Object? value) =>
        value is Map &&
        value.entries.every(
          (entry) =>
              entry.key is String &&
              (entry.value == null ||
                  entry.value is String ||
                  entry.value is bool ||
                  entry.value is num &&
                      (entry.value is! double ||
                          (entry.value as double).isFinite)),
        );
    if (rows.length != raw.length ||
        rows.any((row) {
          final id = positiveResourceId(row['id']);
          final decision = row['decision'];
          final documents = row['documents'];
          if (id == null ||
              !ids.add(id) ||
              row['version'] is! int ||
              (row['version'] as int) < 1 ||
              row['current'] is! bool ||
              row['reason'] is! String ||
              (row['reason'] as String).trim().isEmpty ||
              strictDateTime(row['requested_at']) == null ||
              !primitiveMap(row['before']) ||
              !primitiveMap(row['proposed']) ||
              mapOf(row['proposed']).isEmpty ||
              documents is! Map ||
              !documents.entries.every(
                (entry) =>
                    entry.key is String &&
                    (entry.value == null || entry.value is String),
              )) {
            return true;
          }
          if (decision == null) return false;
          if (decision is! Map) return true;
          final details = mapOf(decision);
          return positiveResourceId(details['id']) == null ||
              !['approve', 'reject'].contains(details['action']) ||
              strictDateTime(details['decided_at']) == null ||
              details['reason'] != null && details['reason'] is! String ||
              details['actor'] != null && details['actor'] is! String;
        })) {
      return null;
    }
    return rows;
  }

  bool get _choicesValid {
    final raw = subject['fields'];
    if (raw is! List || raw.isEmpty) return false;
    final rows = _choiceRows;
    final keys = <String>{};
    return rows.length == raw.length &&
        rows.every((choice) {
          final key = choice['key'], label = choice['label'];
          return key is String &&
              key.trim().isNotEmpty &&
              label is String &&
              label.trim().isNotEmpty &&
              keys.add(key);
        });
  }

  List<Map<String, dynamic>> get choices =>
      _choicesValid ? _choiceRows : const [];
  List<String> get _requiredDocuments =>
      stringsOf(subject['required_documents']);
  List<String>? get _selectedOptions =>
      uniqueStringOptions(selected['options']);
  bool get _selectedUsesOptions =>
      selected['type'] == 'select' ||
      selected['options'] is List && (selected['options'] as List).isNotEmpty;
  bool get _selectedOptionsValid =>
      !_selectedUsesOptions || (_selectedOptions?.isNotEmpty ?? false);
  bool get _requiredDocumentsValid {
    final value = subject['required_documents'];
    return value == null ||
        value is List && value.every((kind) => kind is String);
  }

  Map<String, dynamic> get selected =>
      choices.where((f) => f['key'] == _field).firstOrNull ??
      {'key': 'birthday', 'label': 'Birth date', 'type': 'date', 'options': []};
  bool get _selectedUsesText =>
      selected['type'] != 'date' && !_selectedUsesOptions;
  TextLengthBounds? get _selectedTextBounds => _selectedUsesText
      ? parseTextLengthBounds(
          selected,
          defaultMinimum: _minimumLength(_field),
          defaultMaximum: _maximumLength(_field),
        )
      : null;
  @override
  void initState() {
    super.initState();
    _resetValue();
  }

  void _resetValue() {
    if (!choices.any((choice) => choice['key'] == _field)) {
      _field = choices.firstOrNull?['key']?.toString() ?? '';
    }
    _value.text = mapOf(subject['values'])[_field]?.toString() ?? '';
  }

  @override
  void didUpdateWidget(IdentitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!hasBuyerAccess) return;
    final previous = mapOf(
      mapOf(oldWidget.page.props['identityCorrection'])['subject'],
    )['source_token'];
    final tokenChanged = previous != subject['source_token'];
    if (tokenChanged || !choices.any((choice) => choice['key'] == _field)) {
      _resetValue();
      if (tokenChanged) {
        _files.clear();
        _conflict = false;
        success = 'Recorded identity details changed. Review the current values before requesting a correction.';
      }
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
    checkBuyerAccount();
    if (file != null && mounted) setState(() => _files[key] = file);
    return null;
  }, validate: false);
  void _view(String url, String title) {
    if (!ensureBuyerAccess()) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateDocumentPage(
          repository: widget.repository,
          path: url,
          title: title,
          account: accountScope,
        ),
      ),
    );
  }

  void _application() {
    if (!ensureBuyerAccess()) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ApplicationEditor(
          repository: widget.repository,
          page: widget.page,
          onSaved: widget.onChanged,
          account: accountScope,
        ),
      ),
    );
  }

  Future<void> _date() async {
    if (!ensureBuyerAccess()) return;
    final now = DateTime.now();
    final initial =
        strictDateOnly(_value.text) ??
        DateTime(now.year - 20, now.month, now.day);
    final result = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(1900)) || initial.isAfter(now)
          ? now
          : initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (!ensureBuyerAccess()) return;
    if (result != null && mounted) {
      setState(() => _value.text = result.toIso8601String().split('T').first);
    }
  }

  Future<void> _submit() async {
    if (_conflict) return;
    await perform(() async {
      if (!_choicesValid) {
        throw const BackendException(
          'Identity correction fields could not be confirmed. Reload your current profile before requesting a correction.',
        );
      }
      if (!_requiredDocumentsValid) {
        throw const BackendException(
          'Required identity documents could not be confirmed. Reload your current profile before requesting a correction.',
        );
      }
      if (_selectedUsesText && _selectedTextBounds == null) {
        throw const BackendException(
          'The identity field requirements could not be confirmed. Reload your current profile before requesting a correction.',
        );
      }
      if (_selectedUsesOptions && !_selectedOptionsValid) {
        throw const BackendException(
          'Choices for this identity field could not be confirmed. Reload your current profile before requesting a correction.',
        );
      }
      final token = subject['source_token'];
      final value = _value.text.trim();
      if (token is! String ||
          RegExp(r'^[a-f0-9]{64}$').stringMatch(token) != token ||
          !choices.any((choice) => choice['key'] == _field)) {
        throw const BackendException(
          'The identity form could not be confirmed. Reload your current profile before requesting a correction.',
        );
      }
      if (value ==
          (mapOf(subject['values'])[_field]?.toString().trim() ?? '')) {
        throw const BackendException(
          'Change the reviewed detail before requesting a correction.',
        );
      }
      if (selected['type'] == 'date') {
        final date = strictDateOnly(value);
        final today = DateTime.now().toUtc().add(const Duration(hours: 8));
        final day = DateTime(today.year, today.month, today.day);
        if (date == null ||
            date.toIso8601String().split('T').first != value ||
            !date.isBefore(day)) {
          throw const BackendException(
            'Choose a real birth date before today.',
          );
        }
      }
      if (_selectedUsesOptions && !_selectedOptions!.contains(value)) {
        throw const BackendException('Choose an available corrected value.');
      }
      try {
        final result = await widget.repository.json(
          '/account/identity-corrections',
          {
            'source_token': token,
            'shop_id': subject['shop_id'],
            'changes': {_field: value},
            'reason': _reason.text.trim(),
          },
          files: _files.values.toList(),
        );
        checkBuyerAccount();
        if (result['id'] is! int || (result['id'] as int) < 1) {
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

  int _minimumLength(String key) => switch (key) {
    'name' || 'first_name' || 'last_name' => 2,
    'middle_name' => 1,
    'address' => 5,
    'city' || 'province' || 'municipality' || 'barangay' => 2,
    'postal_code' => 4,
    _ => 1,
  };

  int _maximumLength(String key) => switch (key) {
    'first_name' || 'middle_name' || 'last_name' => 50,
    'name' => 100,
    'address' => 500,
    'city' || 'province' || 'municipality' || 'barangay' => 255,
    'postal_code' => 4,
    _ => 100,
  };

  @override
  Widget build(BuildContext context) {
    final requests = _validatedRequests;
    return content([
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
            ? user['kyc_feedback']?.toString() ?? 'Submit a clear, valid government photo ID for another review.'
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
          onPressed: busy ? null : _application,
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
          Text(
            _files['id_document']!.name,
            style: const TextStyle(height: 1.7),
          ),
          SubmitButton(
            label: 'Submit ID for Verification',
            busy: busy,
            onPressed: () => perform(() async {
              final result = await widget.repository.mutate(
                '/buyer/kyc/upload',
                {},
                files: [_files['id_document']!],
              );
              checkBuyerAccount(result: result);
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
        if (!_choicesValid)
          const Notice(
            'Identity correction fields could not be confirmed. Reload your current profile before requesting a correction.',
            error: true,
          ),
        DropdownButtonFormField<String>(
          key: ValueKey(Object.hashAll(choices.map((choice) => choice['key']))),
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
          ],
          onChanged: busy || _conflict || !_choicesValid
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
        else if (_selectedUsesOptions)
          if (!_selectedOptionsValid)
            Notice(
              'Choices for ${selected['label']} could not be confirmed. Reload your current profile before requesting a correction.',
              error: true,
            )
          else
            DropdownButtonFormField<String>(
              key: ValueKey(_field),
              initialValue: _selectedOptions!.contains(_value.text)
                  ? _value.text
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Corrected ${selected['label']}',
              ),
              items: [
                for (final option in _selectedOptions!)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: busy || _conflict
                  ? null
                  : (v) => setState(() => _value.text = v ?? ''),
              validator: (v) => v == null ? 'Choose a value.' : null,
            )
        else ...[
          if (_selectedTextBounds == null)
            const Notice(
              'Field length requirements could not be confirmed. Reload your current profile before requesting a correction.',
              error: true,
            ),
          field(
            'changes.$_field',
            'Corrected ${selected['label']}',
            _value,
            required: selected['required'] == true,
            enabled: !_conflict && _selectedTextBounds != null,
            min: _selectedTextBounds?.minimum ?? _minimumLength(_field),
            max: _selectedTextBounds?.maximum ?? _maximumLength(_field),
            keyboard: selected['type'] == 'tel'
                ? TextInputType.phone
                : selected['input_mode'] == 'numeric' || _field == 'postal_code'
                ? TextInputType.number
                : TextInputType.text,
            check: (value) => buyerApplicationFieldError(_field, value),
          ),
        ],
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
          check: buyerNotesTextError,
        ),
        if (!_requiredDocumentsValid)
          const Notice(
            'Required identity documents could not be confirmed. Reload your current profile before requesting a correction.',
            error: true,
          ),
        for (final kind in _requiredDocuments) ...[
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
                : () => perform(() async {
                    await widget.reload();
                    checkBuyerAccount();
                    return null;
                  }, validate: false),
            child: const Text('Reload current identity details'),
          ),
        SubmitButton(
          label: 'Submit correction request',
          busy: busy,
          onPressed:
              _conflict ||
                  !_choicesValid ||
                  !_requiredDocumentsValid ||
                  (_selectedUsesText && _selectedTextBounds == null) ||
                  (_selectedUsesOptions && !_selectedOptionsValid)
              ? null
              : _submit,
        ),
        const Divider(height: 40),
        const ProfileHeading('Requests and decisions', '', Icons.history),
        if (requests == null)
          const Notice(
            'Correction request history could not be confirmed. Refresh before reviewing this history.',
            error: true,
          )
        else if (requests.isEmpty)
          const Text('No correction requests have been recorded.'),
        if (requests != null)
          for (final request in requests)
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
                        onPressed: () =>
                            _view(doc.value, '${doc.key} evidence'),
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
}

class _ApplicationEditor extends StatefulWidget {
  const _ApplicationEditor({
    required this.repository,
    required this.page,
    required this.onSaved,
    required this.account,
  });
  final ProfileRepository repository;
  final WebPage page;
  final ValueChanged<WebPage> onSaved;
  final BuyerAccountScope account;
  @override
  State<_ApplicationEditor> createState() => _ApplicationEditorState();
}

class _ApplicationEditorState
    extends BuyerProfileFormState<_ApplicationEditor> {
  static const _supportedApplicationFieldKeys = {
    'first_name',
    'middle_name',
    'last_name',
    'name',
    'sex',
    'birthday',
    'email',
    'phone',
    'address',
    'city',
    'province',
    'municipality',
    'barangay',
    'postal_code',
  };
  static const _requiredBuyerApplicationFieldKeys = {
    'first_name',
    'middle_name',
    'last_name',
    'sex',
    'email',
    'phone',
    'address',
    'city',
    'province',
    'municipality',
    'barangay',
    'postal_code',
  };

  @override
  ProfileRepository get accountRepository => widget.repository;
  @override
  WebPage get accountPage => widget.page;
  @override
  BuyerAccountScope get parentAccountScope => widget.account;
  late final Map<String, TextEditingController> _values;
  UploadPart? _document;
  @override
  void clearBuyerDraft() {
    _document = null;
    for (final controller in _values.values) {
      controller.clear();
    }
  }

  Map<String, dynamic> get data => mapOf(widget.page.props['buyerApplication']);
  Map<String, dynamic> get application => mapOf(data['application']);
  List<Map<String, dynamic>>? get _confirmedFields {
    final raw = application['fields'];
    if (raw is! List || raw.isEmpty) return null;
    final fields = <Map<String, dynamic>>[];
    final keys = <String>{};
    for (final value in raw) {
      if (value is! Map || value.keys.any((key) => key is! String)) {
        return null;
      }
      final field = <String, dynamic>{
        for (final entry in value.entries) entry.key as String: entry.value,
      };
      final key = field['key'];
      final label = field['label'];
      final type = field['type'];
      final expectedType = switch (key) {
        'sex' => 'select',
        'email' => 'email',
        'phone' => 'tel',
        'birthday' => 'date',
        _ => 'text',
      };
      if (key is! String ||
          !_supportedApplicationFieldKeys.contains(key) ||
          !keys.add(key) ||
          label is! String ||
          label.trim().isEmpty ||
          type != expectedType ||
          field['required'] is! bool) {
        return null;
      }
      fields.add(field);
    }
    return keys.containsAll(_requiredBuyerApplicationFieldKeys) ? fields : null;
  }

  bool get _fieldsValid => _confirmedFields != null;
  List<Map<String, dynamic>> get inputs => (_confirmedFields ?? const [])
      .where(
        (field) => [
          'first_name',
          'middle_name',
          'last_name',
          'name',
          'phone',
          'sex',
          'address',
          'city',
          'province',
          'municipality',
          'barangay',
          'postal_code',
        ].contains(field['key']),
      )
      .toList();
  List<String> _options(Map<String, dynamic> input) =>
      uniqueStringOptions(input['options']) ?? const [];
  bool _validOptions(Map<String, dynamic> input) =>
      _options(input).isNotEmpty &&
      uniqueStringOptions(input['options']) != null;
  TextLengthBounds? _textBounds(Map<String, dynamic> input) =>
      parseTextLengthBounds(input, defaultMinimum: 1, defaultMaximum: 100);
  bool get _hasInvalidTextBounds => inputs.any(
    (input) => input['type'] != 'select' && _textBounds(input) == null,
  );
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
    if (!ensureBuyerAccess()) return;
    final last = strictDateOnly(
      mapOf(data['birth_date_limits'])['adult_maximum'],
    );
    if (last == null) {
      setState(
        () => problem =
            'Birth-date requirements are unavailable. Reload your profile.',
      );
      return;
    }
    final current = strictDateOnly(_values['birthday']!.text);
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
    if (!ensureBuyerAccess()) return;
    if (picked != null && mounted) {
      setState(
        () => _values['birthday']!.text = picked
            .toIso8601String()
            .split('T')
            .first,
      );
    }
  }

  void _viewDocument(String path) {
    if (!ensureBuyerAccess()) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateDocumentPage(
          repository: widget.repository,
          path: path,
          title: 'Identity document on file',
          account: accountScope,
        ),
      ),
    );
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
              if (_hasInvalidTextBounds)
                const Notice(
                  'One or more field length requirements could not be confirmed. Reload your profile before editing those details.',
                  error: true,
                ),
              if (!_fieldsValid)
                const Notice(
                  'Application fields could not be confirmed. Reload your profile before editing or submitting these details.',
                  error: true,
                ),
              for (final input in inputs)
                if (input['type'] == 'select') ...[
                  if (!_validOptions(input))
                    Notice(
                      'Choices for ${input['label']} could not be confirmed. Reload your profile before changing this detail.',
                      error: true,
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue:
                          _options(input).contains(_values[input['key']]!.text)
                          ? _values[input['key']]!.text
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: input['label'].toString(),
                        errorText: errors[input['key']],
                        errorMaxLines: 4,
                      ),
                      items: [
                        for (final option in _options(input))
                          DropdownMenuItem(value: option, child: Text(option)),
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
                    enabled: _textBounds(input) != null,
                    min: _textBounds(input)?.minimum ?? 1,
                    max: _textBounds(input)?.maximum ?? 100,
                    keyboard: input['type'] == 'tel'
                        ? TextInputType.phone
                        : input['input_mode'] == 'numeric' ||
                              input['key'] == 'postal_code'
                        ? TextInputType.number
                        : TextInputType.text,
                    check: (value) => buyerApplicationFieldError(
                      input['key'].toString(),
                      value,
                    ),
                  ),
              OutlinedButton.icon(
                onPressed: busy || !_fieldsValid ? null : _date,
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
                      : () => _viewDocument(data['identity_document_url']),
                  child: const Text('View identity document on file'),
                ),
              OutlinedButton.icon(
                onPressed: busy || !_fieldsValid
                    ? null
                    : () => perform(() async {
                        final document = await pickUpload('id_document');
                        checkBuyerAccount();
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
                onPressed: !_fieldsValid
                    ? null
                    : () => perform(() async {
                        final changes = {
                          for (final value in _values.entries)
                            if (value.value.text.trim() !=
                                mapOf(
                                  application['values'],
                                )[value.key]?.toString())
                              value.key: value.value.text.trim(),
                        };
                        for (final key in changes.keys) {
                          final input = inputs
                              .where((field) => field['key'] == key)
                              .firstOrNull;
                          if (input != null &&
                              input['type'] != 'select' &&
                              _textBounds(input) == null) {
                            throw const BackendException(
                              'Application field requirements could not be confirmed. Reload your profile before changing those details.',
                            );
                          }
                          if (input != null &&
                              input['type'] == 'select' &&
                              (!_validOptions(input) ||
                                  !_options(input).contains(changes[key]))) {
                            throw const BackendException(
                              'Application field choices could not be confirmed. Reload your profile before changing that detail.',
                            );
                          }
                        }
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
                        checkBuyerAccount(result: page);
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
