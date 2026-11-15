import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/resource_ids.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
import '../products/product_widgets.dart';
import 'account_enforcement_notices.dart';

const Map<String, String> deliveryFeedbackTagLabels = {
  'fast_delivery': 'Fast delivery',
  'polite_rider': 'Polite rider',
  'parcel_intact': 'Parcel intact',
  'late_delivery': 'Late delivery',
  'rude_behavior': 'Rude behavior',
  'damaged_outer_box': 'Damaged outer box',
};

const Map<String, ({String title, String description, bool warning})>
_moderationMeta = {
  'excluded_courier_issue': (
    title: 'Excluded from Product Rating (Delivery Issue)',
    description: 'This comment remains visible for transparency, but its star rating does not lower the seller product score because delivery feedback belongs with the courier.',
    warning: true,
  ),
  'held_velocity_review': (
    title: 'Under Automated Quality Review',
    description: 'Temporarily excluded from public product scores pending platform moderation review.',
    warning: true,
  ),
  'removed_policy': (
    title: 'Removed for Policy Violation',
    description: 'Hidden from public product scores under Bagoo Review & Rating Governance.',
    warning: false,
  ),
  'restored': (
    title: 'Restored after Moderation Appeal',
    description: 'Included in public product ratings after platform review.',
    warning: false,
  ),
};

/// Renders Bagoo confidential safety check-ins and separate courier delivery feedback.
class CourierDeliveryFeedbackPanel extends StatefulWidget {
  const CourierDeliveryFeedbackPanel({
    super.key,
    required this.session,
    required this.referer,
    this.deliveryFeedback,
    this.deliveryFeedbackUrl,
    this.safetyCheckinSignals = const [],
    this.disabled = false,
    this.onUpdated,
  });

  final WebSession session;
  final String referer;
  final Map<String, dynamic>? deliveryFeedback;
  final String? deliveryFeedbackUrl;
  final List<Map<String, dynamic>> safetyCheckinSignals;
  final bool disabled;
  final Future<void> Function(WebPage page)? onUpdated;

  @override
  State<CourierDeliveryFeedbackPanel> createState() =>
      _CourierDeliveryFeedbackPanelState();
}

class _CourierDeliveryFeedbackPanelState
    extends State<CourierDeliveryFeedbackPanel> {
  late int _rating;
  late int _timeliness;
  late int _handling;
  late int _communication;
  late Set<String> _tags;
  late final TextEditingController _commentController;
  bool _editing = false;
  bool _busy = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController();
    _syncFromProps();
  }

  @override
  void didUpdateWidget(covariant CourierDeliveryFeedbackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deliveryFeedback != widget.deliveryFeedback) {
      _syncFromProps();
    }
  }

  void _syncFromProps() {
    final fb = widget.deliveryFeedback;
    _rating = _clampRating(amount(fb?['rating'])?.round() ?? 5);
    _timeliness = _clampRating(amount(fb?['timeliness_rating'])?.round() ?? 5);
    _handling = _clampRating(amount(fb?['handling_rating'])?.round() ?? 5);
    _communication = _clampRating(
      amount(fb?['communication_rating'])?.round() ?? 5,
    );
    _tags = fb?['tags'] is List
        ? (fb!['tags'] as List).map((e) => e.toString()).toSet()
        : <String>{};
    _commentController.text = fb?['comment']?.toString() ?? '';
  }

  int _clampRating(int value) => value.clamp(1, 5);

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitSafetyCheckin(int signalId, String response) async {
    if (_busy || widget.disabled) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      final page = await widget.session.submit(
        '/buyer/safety-checkins/$signalId',
        {'response': response, 'notes': ''},
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
              flashSuccess ??
              'Thank you for completing the Bagoo safety check-in.';
        });
      }
    } on BackendException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitFeedback() async {
    final url = widget.deliveryFeedbackUrl;
    if (_busy || widget.disabled || url == null || url.isEmpty) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      final page = await widget.session.submit(url, {
        'rating': _rating,
        'timeliness_rating': _timeliness,
        'handling_rating': _handling,
        'communication_rating': _communication,
        'comment': _commentController.text.trim(),
        'tags': _tags.toList(),
      }, referer: widget.referer);
      assertNoInertiaErrors(page);
      final flashSuccess = mapOf(page.props['flash'])['success']?.toString();
      if (widget.onUpdated != null) {
        await widget.onUpdated!(page);
      }
      if (mounted) {
        setState(() {
          _editing = false;
          _statusMessage = flashSuccess ?? 'Your delivery & courier feedback has been saved separately from product ratings.';
        });
      }
    } on BackendException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFeedback =
        widget.deliveryFeedback != null || widget.deliveryFeedbackUrl != null;
    if (!hasFeedback && widget.safetyCheckinSignals.isEmpty) {
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
        if (widget.safetyCheckinSignals.isNotEmpty)
          ProductPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProductHeading('Bagoo Safety Check-in'),
                const Text(
                  'Help keep transactions protected inside the app. Your response stays confidential.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 12),
                for (final signal in widget.safetyCheckinSignals)
                  _buildSignalCard(signal),
              ],
            ),
          ),
        if (hasFeedback)
          ProductPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProductHeading('Courier & Delivery Experience'),
                const Text(
                  'Rates rider handling and speed separately from the product itself.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 12),
                if (widget.deliveryFeedback != null && !_editing)
                  _buildSummary(widget.deliveryFeedback!)
                else if (widget.deliveryFeedbackUrl != null)
                  _buildForm(),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSignalCard(Map<String, dynamic> signal) {
    final signalId = positiveResourceId(signal['id']);
    final summary =
        signal['summary']?.toString() ??
        'Did everything remain safely inside Bagoo for this order?';
    final response = signal['buyer_checkin_response']?.toString();

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
          if (signal['reference'] != null)
            Text(
              'Check-in ${signal['reference']}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9F1239),
              ),
            ),
          const SizedBox(height: 4),
          Text(summary, style: const TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 10),
          if (response != null && response.isNotEmpty)
            Text(
              response == 'reported_bypass'
                  ? 'Recorded: Off-app contact / bypass reported.'
                  : 'Recorded: Normal transaction on Bagoo.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF047857),
              ),
            )
          else if (signalId != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || widget.disabled
                      ? null
                      : () =>
                            _submitSafetyCheckin(signalId, 'safe_on_platform'),
                  child: const Text('Everything is normal on Bagoo'),
                ),
                OutlinedButton(
                  onPressed: _busy || widget.disabled
                      ? null
                      : () => _submitSafetyCheckin(signalId, 'reported_bypass'),
                  child: const Text('I was asked to transact off-app'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSummary(Map<String, dynamic> fb) {
    final canEditOnce =
        fb['edited_at'] == null && widget.deliveryFeedbackUrl != null;
    final tags = fb['tags'] is List
        ? (fb['tags'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overall: ${fb['rating']}/5 · Timeliness: ${fb['timeliness_rating']}/5 · Handling: ${fb['handling_rating']}/5 · Communication: ${fb['communication_rating']}/5',
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.6),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    deliveryFeedbackTagLabels[tag] ?? tag,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (fb['comment'] != null &&
            fb['comment'].toString().trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            fb['comment'].toString(),
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ],
        const SizedBox(height: 10),
        if (canEditOnce)
          OutlinedButton(
            onPressed: _busy || widget.disabled
                ? null
                : () => setState(() => _editing = true),
            child: const Text('Edit once'),
          )
        else
          const Text(
            'Single delivery feedback edit has already been used.',
            style: TextStyle(fontSize: 12, color: BagooTheme.muted),
          ),
      ],
    );
  }

  Widget _buildForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ratingRow('Overall delivery', _rating, (v) => _rating = v),
      _ratingRow('Timeliness', _timeliness, (v) => _timeliness = v),
      _ratingRow('Parcel handling', _handling, (v) => _handling = v),
      _ratingRow(
        'Rider communication',
        _communication,
        (v) => _communication = v,
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final entry in deliveryFeedbackTagLabels.entries)
            FilterChip(
              label: Text(entry.value),
              selected: _tags.contains(entry.key),
              onSelected: _busy || widget.disabled
                  ? null
                  : (selected) {
                      setState(() {
                        if (selected) {
                          _tags.add(entry.key);
                        } else {
                          _tags.remove(entry.key);
                        }
                      });
                    },
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _commentController,
        enabled: !_busy && !widget.disabled,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Delivery notes (optional)',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _busy || widget.disabled ? null : _submitFeedback,
            child: Text(
              _busy
                  ? 'Saving...'
                  : widget.deliveryFeedback != null
                  ? 'Save Single Edit'
                  : 'Submit Courier Feedback',
            ),
          ),
          if (widget.deliveryFeedback != null)
            TextButton(
              onPressed: _busy || widget.disabled
                  ? null
                  : () {
                      _syncFromProps();
                      setState(() => _editing = false);
                    },
              child: const Text('Cancel'),
            ),
        ],
      ),
    ],
  );

  Widget _ratingRow(
    String label,
    int current,
    void Function(int value) onSelect,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        for (var star = 1; star <= 5; star++)
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: '$label $star stars',
            onPressed: _busy || widget.disabled
                ? null
                : () => setState(() => onSelect(star)),
            icon: Icon(
              star <= current ? Icons.star : Icons.star_border,
              color: star <= current
                  ? const Color(0xFFF59E0B)
                  : BagooTheme.muted,
              size: 20,
            ),
          ),
      ],
    ),
  );
}

/// Renders product review moderation notices and inline buyer appeals.
class ReviewModerationPanel extends StatefulWidget {
  const ReviewModerationPanel({
    super.key,
    required this.session,
    required this.review,
    required this.referer,
    this.disabled = false,
    this.onUpdated,
  });

  final WebSession session;
  final Map<String, dynamic> review;
  final String referer;
  final bool disabled;
  final Future<void> Function(WebPage page)? onUpdated;

  @override
  State<ReviewModerationPanel> createState() => _ReviewModerationPanelState();
}

class _ReviewModerationPanelState extends State<ReviewModerationPanel> {
  final TextEditingController _appealReason = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void dispose() {
    _appealReason.dispose();
    super.dispose();
  }

  Future<void> _submitAppeal() async {
    final url = widget.review['appeal_url']?.toString();
    final reason = _appealReason.text.trim();
    if (url == null || url.isEmpty || _busy || widget.disabled) return;
    if (reason.isEmpty) {
      setState(
        () => _errorMessage =
            'Please explain why this review should be restored or re-scored.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      final page = await widget.session.submit(url, {
        'appeal_reason': reason,
      }, referer: widget.referer);
      assertNoInertiaErrors(page);
      final flashSuccess = mapOf(page.props['flash'])['success']?.toString();
      if (widget.onUpdated != null) {
        await widget.onUpdated!(page);
      }
      if (mounted) {
        _appealReason.clear();
        setState(() {
          _open = false;
          _statusMessage =
              flashSuccess ?? 'Your review appeal has been submitted.';
        });
      }
    } on BackendException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.review['moderation_status']?.toString();
    final meta = status != null ? _moderationMeta[status] : null;
    final dispute = widget.review['dispute'] is Map
        ? mapOf(widget.review['dispute'])
        : null;
    final appealUrl = widget.review['appeal_url']?.toString();
    if (meta == null &&
        dispute == null &&
        (appealUrl == null || appealUrl.isEmpty)) {
      return const SizedBox.shrink();
    }

    final isWarning = meta?.warning ?? false;
    final bgColor = isWarning
        ? const Color(0xFFFFFBEB)
        : const Color(0xFFF8FAFC);
    final borderColor = isWarning
        ? const Color(0xFFFCD34D)
        : const Color(0xFFCBD5E1);
    final moderationReason = widget.review['moderation_reason']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta != null) ...[
            Text(
              meta.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              meta.description,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ],
          if (moderationReason != null &&
              moderationReason.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Reason: $moderationReason',
              style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
            ),
          ],
          if (dispute != null) ...[
            const SizedBox(height: 6),
            Text(
              'Review appeal ${dispute['reference'] ?? ''}: ${dispute['status']?.toString().replaceAll('_', ' ') ?? 'recorded'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            if (dispute['appeal_review_notes'] != null &&
                dispute['appeal_review_notes'].toString().trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  dispute['appeal_review_notes'].toString(),
                  style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
                ),
              ),
          ],
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Notice(_statusMessage!),
            ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Notice(_errorMessage!, error: true),
            ),
          if (appealUrl != null && appealUrl.isNotEmpty && dispute == null) ...[
            const SizedBox(height: 8),
            if (!_open)
              OutlinedButton(
                onPressed: _busy || widget.disabled
                    ? null
                    : () => setState(() => _open = true),
                child: const Text('Appeal moderation decision'),
              )
            else ...[
              TextField(
                controller: _appealReason,
                enabled: !_busy && !widget.disabled,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Explain why this review should be restored',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy || widget.disabled ? null : _submitAppeal,
                    child: Text(_busy ? 'Submitting...' : 'Submit appeal'),
                  ),
                  TextButton(
                    onPressed: _busy || widget.disabled
                        ? null
                        : () => setState(() => _open = false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
