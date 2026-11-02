import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/request_id.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/pagination_metadata.dart';
import '../../core/retry_cooldown.dart';
import '../../core/strict_datetime.dart';
import '../../core/verification_cooldown.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/buyer_actions.dart';
import '../products/product_widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

final _sessionIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  return value.map<String, dynamic>(
    (key, entry) => MapEntry(key as String, entry),
  );
}

DateTime? _nullableSessionTime(Object? value) =>
    value == null ? null : strictDateTime(value, requireTimezone: true);

class SessionsSection extends StatefulWidget {
  const SessionsSection({
    super.key,
    required this.repository,
    required this.owner,
    this.active = true,
    this.refreshVersion = 0,
  });
  final ProfileRepository repository;
  final int owner;
  final bool active;
  final int refreshVersion;
  @override
  State<SessionsSection> createState() => _SessionsSectionState();
}

class _SessionsSectionState extends State<SessionsSection>
    with WidgetsBindingObserver {
  late final BuyerAccountScope _account;
  late final int _owner;
  Map<String, dynamic>? _data;
  String? _error, _feedback;
  bool _busy = true;
  int _sessionsPage = 1, _historyPage = 1, _generation = 0;
  bool get _current =>
      _account.isCurrent &&
      identical(_account.session, widget.repository.session) &&
      widget.owner == _owner;

  void _discardPrivate() {
    _account.invalidate();
    _generation++;
    _data = null;
    _feedback = null;
    _busy = false;
    _error = 'Your buyer account changed or access ended. Reopen login activity from your profile.';
  }

  void _accessLost() {
    if (mounted) setState(_discardPrivate);
  }

  bool _ensureCurrent() {
    if (_current) return true;
    _accessLost();
    return false;
  }

  bool _validSessionEntry(
    Map<String, dynamic> entry, {
    required String currentSessionId,
    required bool signInHistory,
  }) {
    final id = entry['id'];
    final device = entry['device'];
    final channel = entry['channel'];
    final method = entry['method'];
    final deviceType = entry['device_type'];
    final network = entry['network'];
    final status = entry['status'];
    final signedInAt = entry['signed_in_at'];
    final lastSeenAt = entry['last_seen_at'];
    final endedAt = entry['ended_at'];

    return id is String &&
        _sessionIdPattern.hasMatch(id) &&
        device is String &&
        device.trim().isNotEmpty &&
        channel is String &&
        channel.trim().isNotEmpty &&
        method is String &&
        method.trim().isNotEmpty &&
        const {'phone', 'tablet', 'computer', 'unknown'}.contains(deviceType) &&
        (network == null ||
            network is String &&
                network.trim().isNotEmpty &&
                network.length <= 64 &&
                !RegExp(r'[\x00-\x1f]').hasMatch(network)) &&
        entry['current'] is bool &&
        (entry['current'] as bool) == (id == currentSessionId) &&
        entry['active'] is bool &&
        const {'active', 'signed_out', 'expired', 'ended'}.contains(status) &&
        (entry['active'] as bool) == (status == 'active') &&
        (signedInAt == null || _nullableSessionTime(signedInAt) != null) &&
        (!signInHistory || signedInAt != null) &&
        (lastSeenAt == null || _nullableSessionTime(lastSeenAt) != null) &&
        (endedAt == null || _nullableSessionTime(endedAt) != null);
  }

  bool _validSessionPage(
    Object? value, {
    required String currentSessionId,
    required bool signInHistory,
  }) {
    final page = _stringKeyedMap(value);
    if (page == null || page['data'] is! List) return false;
    final rows = page['data'] as List;
    if (rows.length > 12 || page['per_page'] != 12) return false;
    final pagination = parsePaginationMetadata(
      page,
      rowCount: rows.length,
      requirePageNumbers: true,
    );
    final expectedLastPage = pagination == null || pagination.total == 0
        ? 1
        : (pagination.total + 11) ~/ 12;
    if (pagination == null || pagination.lastPage != expectedLastPage) {
      return false;
    }
    if (rows.isNotEmpty &&
        (pagination.from != (pagination.currentPage - 1) * 12 + 1 ||
            pagination.to != pagination.from! + rows.length - 1)) {
      return false;
    }

    final ids = <String>{};
    for (final value in rows) {
      final entry = _stringKeyedMap(value);
      if (entry == null ||
          !_validSessionEntry(
            entry,
            currentSessionId: currentSessionId,
            signInHistory: signInHistory,
          )) {
        return false;
      }
      if (!ids.add(entry['id'] as String)) return false;
    }
    return true;
  }

  bool _validSessionsResponse(Map<String, dynamic> data) {
    final owner = data['sessionOwnerId'];
    final currentSessionId = data['currentSessionId'];
    final historyDays = data['historyDays'];
    if (owner is! int ||
        owner != _owner ||
        currentSessionId is! String ||
        !_sessionIdPattern.hasMatch(currentSessionId) ||
        data['canConfirmByEmail'] is! bool ||
        historyDays is! int ||
        historyDays < 0 ||
        !data.containsKey('lastSignIn')) {
      return false;
    }

    final lastSignIn = data['lastSignIn'];
    final validLastSignIn =
        lastSignIn == null ||
        (() {
          final entry = _stringKeyedMap(lastSignIn);
          return entry != null &&
              _validSessionEntry(
                entry,
                currentSessionId: currentSessionId,
                signInHistory: true,
              );
        })();
    return validLastSignIn &&
        _validSessionPage(
          data['sessions'],
          currentSessionId: currentSessionId,
          signInHistory: false,
        ) &&
        _validSessionPage(
          data['signIns'],
          currentSessionId: currentSessionId,
          signInHistory: true,
        );
  }

  @override
  void initState() {
    super.initState();
    _owner = widget.owner;
    _account = BuyerAccountScope(widget.repository.session);
    if (_owner < 1) _account.invalidate();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ensureCurrent();
  }

  @override
  void didUpdateWidget(SessionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ensureCurrent()) return;
    if (widget.active &&
        (!oldWidget.active ||
            widget.refreshVersion != oldWidget.refreshVersion)) {
      _load();
    }
  }

  @override
  void dispose() {
    _account.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    if (!_ensureCurrent()) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.repository.session.jsonGet(
        '/account/security?sessions_page=$_sessionsPage&history_page=$_historyPage',
      );
      _account.check();
      if (!_current) {
        throw const BackendException(
          'Your buyer account changed.',
          status: 401,
        );
      }
      if (data['sessionOwnerId'] is! int ||
          data['sessionOwnerId'] != _owner ||
          data['currentSessionId'] is! String ||
          !_sessionIdPattern.hasMatch(data['currentSessionId'] as String)) {
        throw const BackendException(
          'Your buyer account changed. Reopen login activity from your profile.',
          status: 401,
        );
      }
      if (!_validSessionsResponse(data)) {
        throw const BackendException(
          'Login activity could not be confirmed for your account.',
        );
      }
      if (mounted && generation == _generation) setState(() => _data = data);
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e.message;
          if (!_current || [401, 403, 404, 419].contains(e.status)) {
            _discardPrivate();
          }
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic>? session) async {
    if (!_ensureCurrent() || _busy || _error != null) return;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RevokeDialog(
        repository: widget.repository,
        session: session,
        canEmail: _data?['canConfirmByEmail'] == true,
        account: _account,
        onAccessLost: _accessLost,
      ),
    );
    if (!mounted || !_ensureCurrent() || result == null) return;
    setState(() => _feedback = result);
    await _load();
  }

  Widget _entry(
    Map<String, dynamic> session, {
    bool actionable = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(switch (session['device_type']) {
                'phone' => Icons.smartphone,
                'tablet' => Icons.tablet_mac,
                _ => Icons.laptop,
              }, color: BagooTheme.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                session['device']?.toString() ?? 'Unknown device',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          session['current'] == true
              ? 'This session'
              : session['active'] == true
              ? 'Signed in'
              : session['status'] == 'expired'
              ? 'Expired'
              : 'Signed out',
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.6),
        ),
        Text(
          '${session['channel'] ?? 'web'} · ${session['method'] ?? 'Not recorded'}\nSigned in: ${readableDateTime(session['signed_in_at'])}\nLast active: ${readableDateTime(session['last_seen_at'])}${session['ended_at'] == null ? '' : '\nEnded: ${readableDateTime(session['ended_at'])}'}',
          style: const TextStyle(
            fontSize: 12,
            height: 1.8,
            color: BagooTheme.muted,
          ),
        ),
        if (session['network'] != null)
          Text(
            'Network: ${session['network']}',
            style: const TextStyle(fontSize: 12, height: 1.7),
          ),
        if (actionable &&
            session['current'] != true &&
            session['active'] == true)
          TextButton(
            onPressed: _busy || _error != null ? null : () => _revoke(session),
            child: const Text('Sign out this session'),
          ),
        const Divider(height: 24),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => !_current
      ? ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ProfileHeading(
              'Login activity unavailable',
              '',
              Icons.lock_outline,
            ),
            Notice(
              'Your buyer account changed or access ended. Reopen login activity from your profile.',
              error: true,
            ),
          ],
        )
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProfilePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProfileHeading(
                    'Login activity',
                    'Manage where you are signed in. Each entry is a browser or app session; several can belong to the same device.',
                    Icons.devices_outlined,
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) ...[
                    Notice(_error!, error: true),
                    TextButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      onPressed: () => BuyerActions.login(context),
                      child: const Text('Sign in again'),
                    ),
                  ],
                  if (_feedback != null) Notice(_feedback!),
                  if (_data != null) ...[
                    if (_data!['lastSignIn'] != null)
                      Text(
                        'Latest sign-in: ${readableDateTime(mapOf(_data!['lastSignIn'])['signed_in_at'])}',
                        style: const TextStyle(fontSize: 12, height: 1.7),
                      ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh login activity'),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Signed-in sessions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final session in mapsOf(
                      mapOf(_data!['sessions'])['data'],
                    ))
                      _entry(session, actionable: true),
                    if (mapsOf(mapOf(_data!['sessions'])['data']).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No other signed-in sessions found.'),
                      ),
                    ProfilePagination(mapOf(_data!['sessions']), (page) {
                      _sessionsPage = page;
                      _load();
                    }, disabled: _busy),
                    OutlinedButton(
                      onPressed:
                          _busy ||
                              _error != null ||
                              !mapsOf(mapOf(_data!['sessions'])['data']).any(
                                (s) =>
                                    s['active'] == true && s['current'] != true,
                              )
                          ? null
                          : () => _revoke(null),
                      child: const Text('Sign out other sessions'),
                    ),
                    const Divider(height: 40),
                    Text(
                      'Recent sign-ins · ${_data!['historyDays']} days',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final session in mapsOf(
                      mapOf(_data!['signIns'])['data'],
                    ))
                      _entry(session),
                    ProfilePagination(mapOf(_data!['signIns']), (page) {
                      _historyPage = page;
                      _load();
                    }, disabled: _busy),
                  ],
                ],
              ),
            ),
          ],
        );
}

class _RevokeDialog extends StatefulWidget {
  const _RevokeDialog({
    required this.repository,
    required this.session,
    required this.canEmail,
    required this.account,
    required this.onAccessLost,
  });
  final ProfileRepository repository;
  final Map<String, dynamic>? session;
  final bool canEmail;
  final BuyerAccountScope account;
  final VoidCallback onAccessLost;
  @override
  State<_RevokeDialog> createState() => _RevokeDialogState();
}

class _RevokeDialogState extends ProfileFormState<_RevokeDialog>
    with WidgetsBindingObserver {
  late final BuyerAccountScope _account;
  final _password = TextEditingController(), _code = TextEditingController();
  final _intent = requestId();
  String _method = 'password';
  Map<String, dynamic>? _submitted;
  DateTime? _nextCode;
  Timer? _timer;
  late final RetryCooldown _revokeCooldown;
  int _cooldown = 0;
  bool _lost = false, _submittingRevoke = false;
  @override
  void initState() {
    super.initState();
    _account = widget.account.fork();
    _revokeCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
    _lost = !_account.isCurrent;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onFailure(BackendException error) {
    if (!_account.isCurrent || [401, 403, 404, 419].contains(error.status)) {
      _account.invalidate();
      _lost = true;
      _timer?.cancel();
      _revokeCooldown.clear(notify: false);
      _submitted = null;
      _password.clear();
      _code.clear();
      problem = null;
      success = null;
      errors = {};
      widget.onAccessLost();
    } else if (error.status == 429) {
      if (_submittingRevoke) {
        _revokeCooldown.start(
          error.data,
          retryAt: error.retryAt,
          notify: false,
        );
      } else {
        _wait(error.data, retryAt: error.retryAt);
      }
    } else if (error.status == 422 || error.fields.isNotEmpty) {
      _submitted = null;
    }
  }

  @override
  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) {
    if (!_account.isCurrent || _lost) {
      if (mounted) {
        setState(
          () => onFailure(
            const BackendException('Your buyer account changed.', status: 401),
          ),
        );
      }
      return Future.value(false);
    }
    return super.perform(action, validate: validate);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_account.isCurrent && mounted) {
      setState(
        () => onFailure(
          const BackendException('Your buyer account changed.', status: 401),
        ),
      );
    }
  }

  @override
  void dispose() {
    _account.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _revokeCooldown.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async => perform(() async {
    final data = await widget.repository.json('/account/security/code', {});
    _account.check();
    if (data['success'] != true) {
      throw const BackendException('The confirmation email was not confirmed.');
    }
    _wait(data);
    return 'Code sent to your verified sign-in email. It expires after ten minutes.';
  }, validate: false);

  void _wait(Map<String, dynamic> data, {DateTime? retryAt}) {
    _nextCode = verificationCooldownDeadline(data, retryAt: retryAt);
    _cooldown = (_nextCode!.difference(DateTime.now()).inMilliseconds / 1000)
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
            (_nextCode!.difference(DateTime.now()).inMilliseconds / 1000)
                .ceil()
                .clamp(0, 3600),
      );
      if (_cooldown == 0) timer.cancel();
    });
  }

  Future<void> _submit() async {
    if (_revokeCooldown.active) return;
    _submittingRevoke = true;
    try {
      await perform(() async {
        _submitted ??= jsonDecode(
          jsonEncode({
            'request_token': _intent,
            'confirmation_method': _method,
            'current_password': _method == 'password' ? _password.text : null,
            'code': _method == 'email' ? _code.text : null,
          }),
        ) as Map<String, dynamic>;
        final data = await widget.repository.json(
          widget.session == null
              ? '/account/security/sessions/revoke-others'
              : '/account/security/sessions/${Uri.encodeComponent(widget.session!['id'])}/revoke',
          _submitted!,
        );
        _account.check();
        if (data['reference'] is! String ||
            !_sessionIdPattern.hasMatch(data['reference'] as String) ||
            data['affected_count'] is! int ||
            data['affected_count'] < 0 ||
            data['message'] is! String ||
            (data['message'] as String).trim().isEmpty) {
          throw const BackendException(
            'Sign-out could not be confirmed. Refresh login activity before retrying.',
          );
        }
        if (mounted) Navigator.pop(context, data['message']);
        return null;
      });
    } finally {
      _submittingRevoke = false;
    }
    if (mounted && errors.isNotEmpty) setState(() => _submitted = null);
  }

  @override
  Widget build(BuildContext context) => _lost || !_account.isCurrent
      ? Dialog(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Notice(
                  'Your buyer account changed or access ended. Close this confirmation and reopen login activity from your profile.',
                  error: true,
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        )
      : PopScope(
          canPop: !busy,
          child: Dialog(
            child: SizedBox(
              width: 520,
              height: MediaQuery.sizeOf(context).height * .8,
              child: content([
                ProfileHeading(
                  widget.session == null
                      ? 'Sign out other sessions?'
                      : 'Sign out this session?',
                  widget.session == null
                      ? 'End other browser and app sessions. Your current session stays open.'
                      : '${widget.session!['device']} will need to sign in again. Your current session stays open.',
                  Icons.phonelink_lock,
                ),
                if (widget.canEmail)
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm it is you',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'password',
                        child: Text('Current password'),
                      ),
                      DropdownMenuItem(
                        value: 'email',
                        child: Text('Email code'),
                      ),
                    ],
                    onChanged: busy || _submitted != null
                        ? null
                        : (v) => setState(() {
                            _method = v!;
                            _password.clear();
                            _code.clear();
                          }),
                  ),
                const SizedBox(height: 20),
                if (_method == 'password')
                  field(
                    'current_password',
                    'Current password',
                    _password,
                    secret: true,
                    max: 4096,
                    enabled: _submitted == null,
                    autofill: const [AutofillHints.password],
                  )
                else ...[
                  OutlinedButton(
                    onPressed: busy || _cooldown > 0 || _submitted != null
                        ? null
                        : _sendCode,
                    child: Text(
                      _cooldown > 0
                          ? 'Resend in ${_cooldown}s'
                          : 'Send email code',
                    ),
                  ),
                  const SizedBox(height: 16),
                  field(
                    'code',
                    'Email code',
                    _code,
                    enabled: _submitted == null,
                    max: 6,
                    keyboard: TextInputType.number,
                    autofill: const [AutofillHints.oneTimeCode],
                    check: (value) => RegExp(r'^\d{6}$').hasMatch(value)
                        ? null
                        : 'Enter the six numbers from your email.',
                  ),
                ],
                if (_submitted != null && !busy)
                  const Notice(
                    'The previous result is uncertain. Retry this same request or close and refresh login activity.',
                    error: true,
                  ),
                SubmitButton(
                  label: _revokeCooldown.active
                      ? 'Retry sign-out in ${_revokeCooldown.remainingSeconds}s'
                      : _submitted == null
                      ? 'Confirm sign out'
                      : 'Retry same sign-out request',
                  onPressed: _revokeCooldown.active ? null : _submit,
                  busy: busy,
                ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ]),
            ),
          ),
        );
}
