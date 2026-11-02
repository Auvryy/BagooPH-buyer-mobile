import 'package:flutter/material.dart';

import '../../core/application_text_validation.dart';
import '../../core/buyer_repository.dart';
import '../../core/retry_cooldown.dart';
import '../../core/resource_ids.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_widgets.dart';
import 'profile_widgets.dart';

class AccountStatusPage extends StatefulWidget {
  const AccountStatusPage({
    super.key,
    required this.repository,
    this.onIdentity,
  });
  final BuyerRepository repository;
  final VoidCallback? onIdentity;
  @override
  State<AccountStatusPage> createState() => _AccountStatusPageState();
}

class _AccountStatusPageState extends ProfileFormState<AccountStatusPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> _status = {};
  final _drafts = <String, TextEditingController>{};
  late final RetryCooldown _requestCooldown;
  Object? _owner;
  bool _conflict = false;
  String _key(Map<String, dynamic> source) =>
      '${source['type']}:${source['id']}:${source['source_token']}';
  @override
  void initState() {
    super.initState();
    _requestCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) _load();
  }

  @override
  void onFailure(BackendException error) {
    if (error.status == 409) _conflict = true;
    if ([401, 403, 419].contains(error.status)) {
      _requestCooldown.clear(notify: false);
      _status = {};
      for (final draft in _drafts.values) {
        draft.clear();
      }
    }
  }

  Future<void> _load() async => perform(() async {
    await _fetch();
    return null;
  }, validate: false);
  Future<void> _fetch() async {
    if (mounted && _status.isNotEmpty) setState(() => _status = {});
    final page = await widget.repository.document('/account/status');
    widget.repository.requireNoErrors(page);
    final status = mapOf(page.props['status']);
    final account = mapOf(status['account']);
    final accountId = positiveResourceId(account['id']);
    if (page.component != 'Auth/AccountStatus' ||
        accountId == null ||
        page.user?['role'] != 'buyer' ||
        positiveResourceId(page.user?['id']) != accountId ||
        _owner != null && _owner != accountId) {
      throw const BackendException(
        'Account status is unavailable for this buyer session.',
        status: 401,
      );
    }
    final sourcesValue = status['sources'];
    final sources = mapsOf(sourcesValue);
    final requestHistoryValue = status['requests'];
    final requests = mapsOf(requestHistoryValue);
    final emailUpdateValue = status['email_update'];
    final emailUpdate = emailUpdateValue is Map
        ? mapOf(emailUpdateValue)
        : <String, dynamic>{};
    final emailUpdateValid =
        emailUpdateValue == null ||
        emailUpdateValue is Map &&
            emailUpdate['pending'] is bool &&
            (emailUpdate['pending'] != true ||
                emailUpdate['attempts'] is int &&
                    (emailUpdate['attempts'] as int) >= 0);
    final sourceKeys = <String>{};
    final requestIds = <int>{};
    if (sourcesValue is! List ||
        sources.length != sourcesValue.length ||
        sources.any((source) {
          final id = positiveResourceId(source['id']);
          final type = source['type'];
          final token = source['source_token'];
          final pendingId = source['pending_request_id'];
          return id == null ||
              type is! String ||
              type.trim().isEmpty ||
              token is! String ||
              RegExp(r'^[a-f0-9]{64}$').stringMatch(token) != token ||
              source['status'] is! String ||
              (source['status'] as String).trim().isEmpty ||
              pendingId != null && positiveResourceId(pendingId) == null ||
              !sourceKeys.add(_key(source));
        }) ||
        requestHistoryValue is! List ||
        requests.length != requestHistoryValue.length ||
        requests.any((request) {
          final id = positiveResourceId(request['id']);
          final createdAt = request['created_at'];
          final decision = request['decision'];
          return id == null ||
              !requestIds.add(id) ||
              request['status'] is! String ||
              (request['status'] as String).trim().isEmpty ||
              request['message'] is! String ||
              createdAt is! String ||
              strictDateTime(createdAt) == null ||
              decision != null && decision is! Map;
        }) ||
        !emailUpdateValid) {
      throw const BackendException(
        'Account status details could not be confirmed. Refresh the status.',
      );
    }
    if (!mounted) return;
    final keys = sources.map(_key).toSet();
    setState(() {
      _owner = accountId;
      _status = status;
      _conflict = false;
      for (final key
          in _drafts.keys.where((key) => !keys.contains(key)).toList()) {
        _drafts.remove(key)!.dispose();
      }
    });
  }

  Future<void> _submit(Map<String, dynamic> source) async {
    if (_requestCooldown.active ||
        _conflict ||
        source['pending_request_id'] != null) {
      return;
    }
    final subjectId = positiveResourceId(source['id']);
    final token = source['source_token'];
    final sourceType = source['type'];
    final currentSources = mapsOf(_status['sources'])
        .where((current) => _key(current) == _key(source))
        .toList();
    if (subjectId == null ||
        sourceType is! String ||
        sourceType.trim().isEmpty ||
        token is! String ||
        RegExp(r'^[a-f0-9]{64}$').stringMatch(token) != token ||
        currentSources.length != 1 ||
        currentSources.single['pending_request_id'] != null) {
      setState(
        () =>
            problem = 'This review request is unavailable. Refresh the status.',
      );
      return;
    }
    final activeSource = currentSources.single;
    final key = _key(activeSource);
    final message = _drafts[key]?.text.trim() ?? '';
    final length = message.runes.length;
    if (length < 20 || length > 2000) {
      setState(() => problem = 'Explain your request in 20–2,000 characters.');
      return;
    }
    final textError = buyerNotesTextError(message);
    if (textError != null) {
      setState(() => problem = textError);
      return;
    }
    await perform(() async {
      late final Map<String, dynamic> result;
      try {
        result = await widget.repository.session.jsonPost(
          '/account/review-requests',
          {
            'subject_type': activeSource['type'],
            'subject_id': subjectId,
            'source_token': activeSource['source_token'],
            'message': message,
          },
        );
      } on BackendException catch (error) {
        if (error.status == 429) {
          _requestCooldown.start(
            error.data,
            retryAt: error.retryAt,
            notify: false,
          );
        }
        rethrow;
      }
      if (positiveResourceId(result['id']) == null ||
          result['status'] is! String) {
        throw const BackendException(
          'Your review request was not confirmed. Refresh the status before trying again.',
        );
      }
      if (mounted) _drafts[key]?.clear();
      await _fetch();
      return 'Review requested. Your access changes only after a server decision.';
    }, validate: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestCooldown.dispose();
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Account status'),
      actions: [
        IconButton(
          tooltip: 'Refresh account status',
          onPressed: busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: content([
            ProfileHeading(
              _status['title']?.toString() ?? 'Account status',
              _status['message']?.toString() ??
                  'Review the recorded status and any restriction notices.',
              Icons.manage_accounts_outlined,
            ),
            if (_status.isNotEmpty) ...[
              Text(
                '${mapOf(_status['account'])['name']} · ${mapOf(_status['account'])['email']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.7,
                ),
              ),
              Text(
                'Account: ${mapOf(_status['account'])['status']} · Identity: ${mapOf(_status['account'])['kyc_status']}',
                style: const TextStyle(height: 1.7),
              ),
              if (_status['can_correct_application'] == true ||
                  _status['can_correct_identity'] == true)
                OutlinedButton.icon(
                  onPressed: busy ? null : widget.onIdentity,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Review identity or application'),
                ),
              if (_status['email_update'] is Map)
                Text(
                  mapOf(_status['email_update'])['pending'] == true
                      ? 'Latest account email update is awaiting delivery (${mapOf(_status['email_update'])['attempts']} attempts).'
                      : 'Latest account email update was delivered.',
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
            ],
            if (_conflict)
              const Notice(
                'Your status changed. Refresh and review the current details before sending another request.',
                error: true,
              ),
            for (final source in mapsOf(_status['sources']))
              ProductPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProductHeading(
                      source['name']?.toString() ?? 'Recorded restriction',
                    ),
                    Text(
                      '${source['status']} · ${source['reason'] ?? 'No additional reason recorded.'}',
                      style: const TextStyle(height: 1.7),
                    ),
                    if (source['pending_request_id'] != null)
                      Text(
                        'Review request #${source['pending_request_id']} is pending.',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.7,
                        ),
                      )
                    else ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: ValueKey(_key(source)),
                        controller: _drafts.putIfAbsent(
                          _key(source),
                          TextEditingController.new,
                        ),
                        enabled: !busy && !_conflict,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          labelText: 'Explain your review request',
                          errorText: errors['message'],
                          errorMaxLines: 4,
                        ),
                      ),
                      FilledButton(
                        onPressed: busy || _conflict || _requestCooldown.active
                            ? null
                            : () => _submit(Map.of(source)),
                        child: Text(
                          _requestCooldown.active
                              ? 'Try again in ${_requestCooldown.remainingSeconds}s'
                              : 'Request a review',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (mapsOf(_status['requests']).isNotEmpty)
              const ProductHeading('Review request history'),
            for (final request in mapsOf(_status['requests']))
              ProductPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request #${request['id']} · ${request['status']}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      readableDateTime(request['created_at']),
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      request['message']?.toString() ?? '',
                      style: const TextStyle(height: 1.7),
                    ),
                    if (request['decision'] is Map)
                      Text(
                        '${mapOf(request['decision'])['action']} · ${mapOf(request['decision'])['reason']}\n${mapOf(request['decision'])['reviewer'] ?? 'Bagoo review team'} · ${readableDateTime(mapOf(request['decision'])['reviewed_at'])}',
                        style: const TextStyle(height: 1.7),
                      ),
                  ],
                ),
              ),
            if (!busy && _status.isEmpty)
              OutlinedButton(
                onPressed: _load,
                child: const Text('Retry account status'),
              ),
          ]),
        ),
      ),
    ),
  );
}
