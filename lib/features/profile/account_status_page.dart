import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
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
  Object? _owner;
  bool _conflict = false;
  String _key(Map<String, dynamic> source) =>
      '${source['type']}:${source['id']}:${source['source_token']}';
  @override
  void initState() {
    super.initState();
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
    final page = await widget.repository.document('/account/status');
    widget.repository.requireNoErrors(page);
    final status = mapOf(page.props['status']);
    final account = mapOf(status['account']);
    if (page.component != 'Auth/AccountStatus' ||
        account['id'] is! num ||
        account['id'] <= 0 ||
        page.user?['role'] != 'buyer' ||
        page.user?['id'] != account['id'] ||
        _owner != null && _owner != account['id']) {
      throw const BackendException(
        'Account status is unavailable for this buyer session.',
        status: 401,
      );
    }
    if (!mounted) return;
    final keys = mapsOf(status['sources']).map(_key).toSet();
    setState(() {
      _owner = account['id'];
      _status = status;
      _conflict = false;
      for (final key
          in _drafts.keys.where((key) => !keys.contains(key)).toList()) {
        _drafts.remove(key)!.dispose();
      }
    });
  }

  Future<void> _submit(Map<String, dynamic> source) async {
    if (_conflict || source['pending_request_id'] != null) return;
    final key = _key(source);
    final message = _drafts[key]?.text.trim() ?? '';
    if (message.length < 20 || message.length > 2000) {
      setState(() => problem = 'Explain your request in 20–2,000 characters.');
      return;
    }
    await perform(() async {
      final result = await widget.repository.session.jsonPost(
        '/account/review-requests',
        {
          'subject_type': source['type'],
          'subject_id': source['id'],
          'source_token': source['source_token'],
          'message': message,
        },
      );
      if (result['id'] is! num ||
          result['id'] <= 0 ||
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
                        onPressed: busy || _conflict
                            ? null
                            : () => _submit(Map.of(source)),
                        child: const Text('Request a review'),
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
