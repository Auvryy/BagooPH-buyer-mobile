import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'auth_shell.dart';
import 'google_auth_controller.dart';
import 'google_auth_repository.dart';
import 'google_identity.dart';
import 'google_registration_form.dart';

class GoogleAuthExit {
  const GoogleAuthExit.authenticated(this.page) : browse = false;
  const GoogleAuthExit.browse() : page = null, browse = true;
  final WebPage? page;
  final bool browse;
}

class GoogleAuthPage extends StatefulWidget {
  const GoogleAuthPage({
    super.key,
    required this.repository,
    required this.provider,
    required this.remember,
  });
  final GoogleAuthRepository repository;
  final GoogleIdentityProvider provider;
  final bool remember;
  @override
  State<GoogleAuthPage> createState() => _GoogleAuthPageState();
}

class _GoogleAuthPageState extends State<GoogleAuthPage>
    with WidgetsBindingObserver {
  late final GoogleAuthController _controller;
  final _summary = GlobalKey();
  final _summaryFocus = FocusNode();
  Timer? _clock;
  bool _finishing = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = GoogleAuthController(
      repository: widget.repository,
      provider: widget.provider,
    )..addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.start(remember: widget.remember));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncClock();

  void _syncClock() {
    final current = ModalRoute.isCurrentOf(context) ?? true;
    final state = WidgetsBinding.instance.lifecycleState;
    final needsClock =
        _controller.coolingDown ||
        _controller.registration != null && !_controller.challengeExpired;
    if (current &&
        (state == null || state == AppLifecycleState.resumed) &&
        needsClock &&
        !_controller.busy) {
      _clock ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _controller.tick(),
      );
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  void _changed() {
    if (!mounted) return;
    _syncClock();
    if (!_finishing &&
        (_controller.authenticatedPage != null ||
            _controller.stage == GoogleAuthStage.canceled)) {
      _finishing = true;
      final page = _controller.authenticatedPage;
      if (page != null) TextInput.finishAutofillContext();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context)
              .pop(page == null ? null : GoogleAuthExit.authenticated(page));
        }
      });
    }
    if (_controller.error != null && _controller.error != _lastError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _summary.currentContext != null) {
          _summaryFocus.requestFocus();
          Scrollable.ensureVisible(_summary.currentContext!);
        }
      });
    }
    _lastError = _controller.error;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return PopScope<GoogleAuthExit>(
      canPop: !c.busy,
      child: AuthShell(
        title: c.registration != null
            ? 'Complete your buyer account'
            : c.stage == GoogleAuthStage.link
            ? 'Connect your Bagoo account'
            : 'Continue with Google',
        subtitle: c.registration != null
            ? 'Your Google identity is verified. Add the details Bagoo needs for a buyer account.'
            : 'Sign in to Bagoo using your Google account.',
        registration: c.registration != null,
        navigationEnabled: !c.busy,
        onBack: () => Navigator.of(context).pop(),
        onBrowse: () =>
            Navigator.of(context).pop(const GoogleAuthExit.browse()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.error != null)
              Padding(
                key: _summary,
                padding: const EdgeInsets.only(bottom: 20),
                child: Focus(
                  focusNode: _summaryFocus,
                  child: Semantics(
                    liveRegion: true,
                    child: Notice(c.error!, error: true),
                  ),
                ),
              ),
            if (c.coolingDown)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Please wait ${c.retrySeconds} seconds before trying again.',
                ),
              ),
            if (c.busy &&
                c.registration == null &&
                c.stage != GoogleAuthStage.link)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      semanticsLabel: 'Connecting Google sign-in',
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Checking your Bagoo sign-in…',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            if (c.stage == GoogleAuthStage.link) _LinkProof(controller: c),
            if (c.registration != null) ...[
              if (c.challengeExpired)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Notice(
                    'This registration session has expired. Check your status or start Google sign-in again.',
                    error: true,
                  ),
                ),
              GoogleRegistrationForm(
                key: ValueKey(c.registration!.nonce),
                repository: widget.repository.buyer,
                contract: c.registration!,
                errors: c.fields,
                disabled: c.busy || c.stage != GoogleAuthStage.registration,
                canSubmit:
                    c.canSubmit && c.stage == GoogleAuthStage.registration,
                busy: c.busy,
                onSubmit: c.complete,
                onEdit: c.clearField,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: c.busy || c.coolingDown
                    ? null
                    : c.refreshRegistration,
                child: const Text('Refresh registration details'),
              ),
            ],
            if (c.stage == GoogleAuthStage.uncertain || c.challengeExpired) ...[
              const SizedBox(height: 16),
              SubmitButton(
                label: 'Check sign-in status',
                busy: c.busy,
                onPressed: c.busy ? null : c.recover,
              ),
            ],
            if (c.stage == GoogleAuthStage.error ||
                c.stage == GoogleAuthStage.uncertain ||
                c.challengeExpired) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: c.busy || c.coolingDown
                    ? null
                    : () => c.start(remember: widget.remember),
                child: const Text('Start Google sign-in again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    _summaryFocus.dispose();
    super.dispose();
  }
}

class _LinkProof extends StatefulWidget {
  const _LinkProof({required this.controller});
  final GoogleAuthController controller;
  @override
  State<_LinkProof> createState() => _LinkProofState();
}

class _LinkProofState extends State<_LinkProof> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  Future<void> _submit() async {
    if (widget.controller.busy ||
        widget.controller.coolingDown ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.link(_password.text);
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'This Google identity matches an existing buyer account. Confirm that account’s Bagoo password to connect it. You can go back and use email sign-in instead.',
        ),
        const SizedBox(height: 20),
        AuthField(
          key: const ValueKey('google-account-password'),
          label: 'Existing Bagoo password',
          controller: _password,
          password: true,
          enabled: !widget.controller.busy && !widget.controller.coolingDown,
          autofillHints: const [AutofillHints.password],
          error: widget.controller.fields['account_password'],
          validator: (v) => (v?.isEmpty ?? true)
              ? 'Enter your existing Bagoo password.'
              : v!.length > 255
              ? 'Use at most 255 characters.'
              : null,
          onChanged: (_) => widget.controller.clearField('account_password'),
          onSubmitted: (_) => _submit(),
        ),
        SubmitButton(
          label: 'Confirm and connect account',
          busy: widget.controller.busy,
          onPressed: widget.controller.busy || widget.controller.coolingDown
              ? null
              : _submit,
        ),
      ],
    ),
  );
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }
}
