import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/resource_ids.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
import '../products/product_widgets.dart';

/// Throws a [BackendException] when an Inertia page carries validation or flash errors.
void assertNoInertiaErrors(WebPage page) {
  if (page.errors.isNotEmpty) {
    throw BackendException(page.errors.values.first, fields: page.errors);
  }
  final error = mapOf(page.props['flash'])['error'];
  if (error is String && error.isNotEmpty) {
    throw BackendException(error);
  }
}

const Map<String, String> enforcementScopeLabels = {
  'warning': 'Formal Account Warning',
  'cod_restricted': 'Cash on Delivery (COD) Restricted',
  'review_restricted': 'Product Review Access Restricted',
  'catalog_visibility_restricted': 'Store Catalog Visibility Restricted',
  'payout_hold': 'Seller Proceeds Hold',
  'pickup_zone_restricted': 'Courier Pickup Restricted',
};

/// Renders active account warnings, sanctions, appeals, and unpaid platform obligations.
class AccountEnforcementNotices extends StatefulWidget {
  const AccountEnforcementNotices({
    super.key,
    required this.session,
    this.sanctions = const [],
    this.penalties = const [],
    this.title = 'Account Restrictions, Warnings & Appeals',
    this.referer = '/account/status',
    this.disabled = false,
    this.onUpdated,
    this.onViewDetails,
  });

  final WebSession session;
  final List<Map<String, dynamic>> sanctions;
  final List<Map<String, dynamic>> penalties;
  final String title;
  final String referer;
  final bool disabled;
  final Future<void> Function(WebPage page)? onUpdated;
  final VoidCallback? onViewDetails;

  @override
  State<AccountEnforcementNotices> createState() =>
      _AccountEnforcementNoticesState();
}

class _AccountEnforcementNoticesState extends State<AccountEnforcementNotices> {
  final Map<int, TextEditingController> _reasons = {};
  final Map<int, TextEditingController> _evidence = {};
  final Set<int> _openAppealIds = {};
  bool _busy = false;
  int? _settlingPenaltyId;
  int? _appealingSanctionId;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void dispose() {
    for (final c in _reasons.values) {
      c.dispose();
    }
    for (final c in _evidence.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _reasonCtrl(int id) =>
      _reasons.putIfAbsent(id, TextEditingController.new);

  TextEditingController _evidenceCtrl(int id) =>
      _evidence.putIfAbsent(id, TextEditingController.new);

  Future<void> _settlePenalty(int penaltyId) async {
    if (_busy || widget.disabled) return;
    setState(() {
      _busy = true;
      _settlingPenaltyId = penaltyId;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      final page = await widget.session.submit(
        '/account/financial-penalties/$penaltyId/settle',
        {},
        referer: widget.referer,
      );
      assertNoInertiaErrors(page);
      final flashSuccess = mapOf(page.props['flash'])['success']?.toString();
      if (widget.onUpdated != null) {
        await widget.onUpdated!(page);
      }
      if (mounted) {
        setState(() {
          _statusMessage =
              flashSuccess ?? 'Obligation settled from Bagoo Wallet.';
        });
      }
    } on BackendException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _settlingPenaltyId = null;
        });
      }
    }
  }

  Future<void> _submitAppeal(int sanctionId) async {
    if (_busy || widget.disabled) return;
    final reason = _reasonCtrl(sanctionId).text.trim();
    if (reason.isEmpty) {
      setState(() => _errorMessage = 'Please explain why you are appealing.');
      return;
    }
    final evidenceNotes = _evidenceCtrl(sanctionId).text.trim();
    setState(() {
      _busy = true;
      _appealingSanctionId = sanctionId;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      final page = await widget.session.submit(
        '/account/enforcement-sanctions/$sanctionId/appeal',
        {'reason': reason, 'evidence_notes': evidenceNotes},
        referer: widget.referer,
      );
      assertNoInertiaErrors(page);
      final flashSuccess = mapOf(page.props['flash'])['success']?.toString();
      if (widget.onUpdated != null) {
        await widget.onUpdated!(page);
      }
      if (mounted) {
        _reasonCtrl(sanctionId).clear();
        _evidenceCtrl(sanctionId).clear();
        setState(() {
          _openAppealIds.remove(sanctionId);
          _statusMessage =
              flashSuccess ?? 'Appeal submitted for independent review.';
        });
      }
    } on BackendException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _appealingSanctionId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sanctions.isEmpty && widget.penalties.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Notice(_statusMessage!),
          ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Notice(_errorMessage!, error: true),
          ),
        if (widget.penalties.isNotEmpty)
          ProductPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProductHeading('Unpaid Platform Obligations'),
                const Text(
                  'Unpaid losses or fees caused by policy violations trigger automatic account restrictions until settled.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 12),
                for (final penalty in widget.penalties)
                  _buildPenaltyCard(penalty),
              ],
            ),
          ),
        if (widget.sanctions.isNotEmpty)
          ProductPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProductHeading(widget.title),
                const Text(
                  'Review why a sanction was applied, what triggered it, or submit an appeal for independent review.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 12),
                for (final sanction in widget.sanctions)
                  _buildSanctionCard(sanction),
                if (widget.onViewDetails != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: widget.disabled || _busy
                          ? null
                          : widget.onViewDetails,
                      child: const Text('Review full account status'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPenaltyCard(Map<String, dynamic> penalty) {
    final penaltyId = positiveResourceId(penalty['id']);
    final outstandingCents = amount(penalty['outstanding_cents']) ?? 0;
    final reference = penalty['reference']?.toString() ?? 'Pending ref';
    final reason = penalty['reason']?.toString() ?? 'Platform obligation';
    final evidence = penalty['evidence_summary']?.toString();
    final isSettling = _busy && _settlingPenaltyId == penaltyId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDA4AF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                pesos(outstandingCents / 100),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF9F1239),
                ),
              ),
              Text(
                reference,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9F1239),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: BagooTheme.ink,
            ),
          ),
          if (evidence != null && evidence.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              evidence,
              style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
            ),
          ],
          if (penaltyId != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy || widget.disabled
                  ? null
                  : () => _settlePenalty(penaltyId),
              child: Text(
                isSettling ? 'Settling...' : 'Settle via Bagoo Wallet',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSanctionCard(Map<String, dynamic> sanction) {
    final sanctionId = positiveResourceId(sanction['id']);
    final scope = sanction['scope']?.toString() ?? '';
    final label = enforcementScopeLabels[scope] ?? scope.replaceAll('_', ' ');
    final reference = sanction['reference']?.toString() ?? '';
    final reason = sanction['reason']?.toString() ?? 'Restriction recorded.';
    final evidence = sanction['evidence_summary']?.toString();
    final autoRelease = sanction['auto_release_on_debt_clear'] == true;
    final appeals = mapsOf(sanction['appeals']);
    final hasPendingAppeal = appeals.any((a) => a['status'] == 'pending');
    final isOpen = sanctionId != null && _openAppealIds.contains(sanctionId);
    final isAppealing = _busy && _appealingSanctionId == sanctionId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              if (reference.isNotEmpty)
                Text(
                  reference,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: BagooTheme.ink,
              height: 1.5,
            ),
          ),
          if (evidence != null && evidence.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Details: $evidence',
              style: const TextStyle(
                fontSize: 12,
                color: BagooTheme.muted,
                height: 1.5,
              ),
            ),
          ],
          if (autoRelease) ...[
            const SizedBox(height: 6),
            const Text(
              'This restriction lifts automatically once all unpaid financial penalties are settled.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF92400E),
              ),
            ),
          ],
          for (final appeal in appeals) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BagooTheme.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appeal ${appeal['reference'] ?? ''}: ${appeal['status']?.toString().toUpperCase() ?? 'RECORDED'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (appeal['review_notes'] != null &&
                      appeal['review_notes'].toString().trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        appeal['review_notes'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: BagooTheme.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (sanctionId != null && !hasPendingAppeal) ...[
            const SizedBox(height: 10),
            if (!isOpen)
              OutlinedButton(
                onPressed: _busy || widget.disabled
                    ? null
                    : () => setState(() => _openAppealIds.add(sanctionId)),
                child: const Text('Appeal Decision'),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _reasonCtrl(sanctionId),
                    enabled: !_busy && !widget.disabled,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Explain why this decision should be reviewed',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _evidenceCtrl(sanctionId),
                    enabled: !_busy && !widget.disabled,
                    decoration: const InputDecoration(
                      labelText: 'Supporting context or reference (optional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy || widget.disabled
                            ? null
                            : () => _submitAppeal(sanctionId),
                        child: Text(
                          isAppealing ? 'Submitting...' : 'Submit Appeal',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy || widget.disabled
                            ? null
                            : () => setState(
                                () => _openAppealIds.remove(sanctionId),
                              ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
