import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
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

class _EmailVerificationLinkPageState extends State<EmailVerificationLinkPage> {
  bool _busy = true, _eligible = false, _verified = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.currentSession();
      if (page?.user?['id'].toString() !=
          (widget.link.pathSegments.length == 3
              ? widget.link.pathSegments[1]
              : null)) {
        throw const BackendException(
          'Sign in to the buyer account named by this verification link.',
        );
      }
      if (mounted) setState(() => _eligible = true);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || !_eligible) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.document(widget.link.toString());
      widget.repository.requireNoErrors(page);
      if (page.user?['role'] != 'buyer' ||
          page.user?['id'].toString() !=
              (widget.link.pathSegments.length == 3
                  ? widget.link.pathSegments[1]
                  : null) ||
          page.user?['email_verified_at'] == null) {
        throw const BackendException(
          'Email verification was not confirmed. The link may have expired; request a new one from Profile.',
        );
      }
      if (mounted) {
        setState(() {
          _verified = true;
          _eligible = false;
        });
      }
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  onPressed: _busy || !_eligible ? null : _verify,
                  child: const Text('Verify my email'),
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
