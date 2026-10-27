import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/request_id.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/buyer_actions.dart';
import '../products/product_widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

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

class _SessionsSectionState extends State<SessionsSection> {
  Map<String, dynamic>? _data;
  String? _error, _feedback;
  bool _busy = true;
  int _sessionsPage = 1, _historyPage = 1, _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SessionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (!oldWidget.active ||
            widget.refreshVersion != oldWidget.refreshVersion)) {
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.repository.session.jsonGet(
        '/account/security?sessions_page=$_sessionsPage&history_page=$_historyPage',
      );
      bool validList(dynamic value) {
        final list = mapOf(value);
        return list['data'] is List &&
            (list['data'] as List).length <= 12 &&
            list['current_page'] is num &&
            list['last_page'] is num &&
            mapsOf(list['data']).every(
              (entry) =>
                  entry['id'] is String &&
                  entry['device'] is String &&
                  entry['current'] is bool &&
                  entry['active'] is bool &&
                  [
                    'active',
                    'signed_out',
                    'expired',
                    'ended',
                  ].contains(entry['status']),
            );
      }

      if (data['sessionOwnerId'] != widget.owner ||
          !validList(data['sessions']) ||
          !validList(data['signIns']) ||
          data['currentSessionId'] is! String) {
        throw const BackendException(
          'Login activity could not be confirmed for your account.',
        );
      }
      if (mounted && generation == _generation) setState(() => _data = data);
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e.message;
          if (e.status == 401 || e.status == 419) _data = null;
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic>? session) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RevokeDialog(
        repository: widget.repository,
        session: session,
        canEmail: _data?['canConfirmByEmail'] == true,
      ),
    );
    if (!mounted || result == null) return;
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
  Widget build(BuildContext context) => ListView(
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              for (final session in mapsOf(mapOf(_data!['sessions'])['data']))
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
                          (s) => s['active'] == true && s['current'] != true,
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
              for (final session in mapsOf(mapOf(_data!['signIns'])['data']))
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
  });
  final ProfileRepository repository;
  final Map<String, dynamic>? session;
  final bool canEmail;
  @override
  State<_RevokeDialog> createState() => _RevokeDialogState();
}

class _RevokeDialogState extends ProfileFormState<_RevokeDialog> {
  final _password = TextEditingController(), _code = TextEditingController();
  final _intent = requestId();
  String _method = 'password';
  Map<String, dynamic>? _submitted;
  DateTime? _nextCode;
  Timer? _timer;
  int _cooldown = 0;
  @override
  void dispose() {
    _timer?.cancel();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async => perform(() async {
    final data = await widget.repository.json('/account/security/code', {});
    if (data['success'] != true) {
      throw const BackendException('The confirmation email was not confirmed.');
    }
    _cooldown = (data['cooldown'] as num?)?.ceil() ?? 60;
    _nextCode = DateTime.now().add(Duration(seconds: _cooldown));
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
    return 'Code sent to your verified sign-in email. It expires after ten minutes.';
  }, validate: false);
  Future<void> _submit() async {
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
      if (data['reference'] is! String ||
          !RegExp(r'^[a-f0-9-]{36}$').hasMatch(data['reference']) ||
          data['affected_count'] is! num ||
          data['affected_count'] < 0 ||
          data['message'] is! String) {
        throw const BackendException(
          'Sign-out could not be confirmed. Refresh login activity before retrying.',
        );
      }
      if (mounted) Navigator.pop(context, data['message']);
      return null;
    });
    if (mounted && errors.isNotEmpty) setState(() => _submitted = null);
  }

  @override
  Widget build(BuildContext context) => PopScope(
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
                ? 'End other browser and rider-app sessions. Your current session stays open.'
                : '${widget.session!['device']} will need to sign in again. Your current session stays open.',
            Icons.phonelink_lock,
          ),
          if (widget.canEmail)
            DropdownButtonFormField<String>(
              initialValue: _method,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Confirm it is you'),
              items: const [
                DropdownMenuItem(
                  value: 'password',
                  child: Text('Current password'),
                ),
                DropdownMenuItem(value: 'email', child: Text('Email code')),
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
                _cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Send email code',
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
            label: _submitted == null
                ? 'Confirm sign out'
                : 'Retry same sign-out request',
            onPressed: _submit,
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
