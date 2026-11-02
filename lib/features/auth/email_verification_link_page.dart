import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/retry_cooldown.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';

class EmailVerificationLinkPage extends StatefulWidget {
  const EmailVerificationLinkPage({
    super.key,
    required this.repository,
    required this.link,
  });
  final BuyerRepository repository;
  final Uri link;
  @override
  State<EmailVerificationLinkPage> createState() =>
      _EmailVerificationLinkPageState();
}

class _EmailVerificationLinkPageState extends State<EmailVerificationLinkPage>
    with WidgetsBindingObserver {
  bool _busy = true, _eligible = false, _verified = false;
  late final RetryCooldown _verifyCooldown;
  int _generation = 0;
  int? _eligibleEpoch;
  String? _error;

  int? get _linkedOwner {
    final segments = widget.link.pathSegments;
    if (segments.length != 3 || segments.first != 'verify-email') return null;
    final id = int.tryParse(segments[1]);
    return id != null && id > 0 ? id : null;
  }

  @override
  void initState() {
    super.initState();
    _verifyCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didUpdateWidget(covariant EmailVerificationLinkPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.link != widget.link) {
      _check();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy && !_verified) {
      _check();
    }
  }

  Future<void> _check() async {
    final generation = ++_generation;
    final epoch = widget.repository.session.identityEpoch;
    setState(() {
      _busy = true;
      _eligible = false;
      _eligibleEpoch = null;
      _verified = false;
      _error = null;
    });
    try {
      final page = await widget.repository.currentSession();
      if (!mounted || generation != _generation) return;
      if (epoch != widget.repository.session.identityEpoch) {
        setState(() {
          _error = 'Your buyer account changed. Check again before continuing.';
        });
        return;
      }
      if (_linkedOwner == null ||
          page?.user?['role'] != 'buyer' ||
          page?.user?['id'] != _linkedOwner) {
        throw const BackendException(
          'Sign in to the buyer account named by this verification link.',
        );
      }
      setState(() {
        _eligible = true;
        _eligibleEpoch = epoch;
      });
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _verify() async {
    if (_busy || !_eligible || _verifyCooldown.active) return;
    final epoch = widget.repository.session.identityEpoch;
    if (_eligibleEpoch != epoch) {
      await _check();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.document(widget.link.toString());
      widget.repository.requireNoErrors(page);
      if (!mounted || generation != _generation) return;
      if (epoch != widget.repository.session.identityEpoch) {
        setState(() {
          _eligible = false;
          _eligibleEpoch = null;
          _error = 'Your buyer account changed. Check again before continuing.';
        });
        return;
      }
      final verifiedAt = page.user?['email_verified_at'];
      if (page.user?['role'] != 'buyer' ||
          page.user?['id'] != _linkedOwner ||
          verifiedAt is! String ||
          strictDateTime(verifiedAt, requireTimezone: true) == null) {
        throw const BackendException(
          'Email verification was not confirmed. The link may have expired; request a new one from Profile.',
        );
      }
      setState(() {
        _verified = true;
        _eligible = false;
        _eligibleEpoch = null;
      });
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        if (e.status == 429) {
          _verifyCooldown.start(e.data, retryAt: e.retryAt, notify: false);
        }
        setState(() {
          _eligible = false;
          _eligibleEpoch = null;
          _error = epoch == widget.repository.session.identityEpoch
              ? e.message
              : 'Your buyer account changed. Check again before continuing.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _verifyCooldown.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify buyer email')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              if (_busy) const LinearProgressIndicator(),
              Text(
                _verified ? 'Your email is verified.' : 'Confirm verification of your buyer email with this Bagoo link.',
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.7,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_error != null) Notice(_error!, error: true),
              if (!_verified)
                FilledButton(
                  onPressed: _busy || !_eligible || _verifyCooldown.active
                      ? null
                      : _verify,
                  child: Text(
                    _verifyCooldown.active
                        ? 'Try again in ${_verifyCooldown.remainingSeconds}s'
                        : 'Verify my email',
                  ),
                ),
              if (!_eligible && !_verified)
                TextButton(
                  onPressed: _busy ? null : _check,
                  child: const Text('Check signed-in buyer'),
                ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
