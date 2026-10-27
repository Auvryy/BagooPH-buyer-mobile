import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'tracking_controller.dart';
import 'tracking_repository.dart';

class ParcelTrackingPage extends StatefulWidget {
  const ParcelTrackingPage({
    super.key,
    required this.repository,
    this.initialNumber,
  });

  final BuyerRepository repository;
  final String? initialNumber;

  @override
  State<ParcelTrackingPage> createState() => _ParcelTrackingPageState();
}

class _ParcelTrackingPageState extends State<ParcelTrackingPage> {
  final _number = TextEditingController();
  late TrackingController _tracking;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  void _configure() {
    _number.text = widget.initialNumber ?? '';
    _tracking = TrackingController(TrackingRepository(widget.repository));
    _tracking.addListener(_changed);
    final controller = _tracking;
    if (_number.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(controller, _tracking)) unawaited(_lookup());
      });
    }
  }

  @override
  void didUpdateWidget(covariant ParcelTrackingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.initialNumber != widget.initialNumber) {
      _tracking.removeListener(_changed);
      _tracking.dispose();
      _configure();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _lookup() async {
    final input = _number.text;
    try {
      final normalized = normalizeTrackingNumber(input);
      _number.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      FocusManager.instance.primaryFocus?.unfocus();
    } on BackendException {
      // The controller presents the shared validation message beside the field.
    }
    await _tracking.lookup(input);
  }

  Future<void> _retry() =>
      _tracking.result == null ? _lookup() : _tracking.refresh();

  Future<void> _copy(String number) async {
    try {
      await Clipboard.setData(ClipboardData(text: number));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tracking number copied.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select the tracking number to copy it.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _tracking.removeListener(_changed);
    _tracking.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lookup = _tracking.result;
    final parcel = lookup?.parcel;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Track a parcel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gutter = constraints.maxWidth >= 760 ? 28.0 : 16.0;
                return RefreshIndicator(
                  onRefresh: _tracking.refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 0),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _searchPanel(),
                              const SizedBox(height: 16),
                              _privacyNote(),
                              if (_tracking.loading) ...[
                                const SizedBox(height: 20),
                                const LinearProgressIndicator(
                                  semanticsLabel: 'Looking up parcel tracking',
                                ),
                              ],
                              if (_tracking.problem != null) ...[
                                const SizedBox(height: 16),
                                _problem(),
                              ],
                              if (lookup != null && parcel == null) ...[
                                const SizedBox(height: 16),
                                _notFound(lookup),
                              ],
                              if (parcel != null) ...[
                                const SizedBox(height: 20),
                                _resultPanels(
                                  lookup!,
                                  parcel,
                                  constraints.maxWidth >= 840,
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'Recorded milestones',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Latest updates first · Philippine time',
                                  style: TextStyle(
                                    color: BagooTheme.muted,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (lookup == null &&
                                  !_tracking.loading &&
                                  _tracking.problem == null) ...[
                                const SizedBox(height: 24),
                                const _TrackingPanel(
                                  child: Column(
                                    children: [
                                      ExcludeSemantics(
                                        child: Icon(
                                          Icons.local_shipping_outlined,
                                          size: 36,
                                          color: BagooTheme.muted,
                                        ),
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        'Your parcel milestones will appear here.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: BagooTheme.muted,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (parcel != null)
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: gutter),
                          sliver: parcel.milestones.isEmpty
                              ? const SliverToBoxAdapter(
                                  child: _TrackingPanel(
                                    child: Text(
                                      'No milestones are recorded yet. Check again after the next parcel handoff.',
                                      style: TextStyle(
                                        height: 1.5,
                                        color: BagooTheme.muted,
                                      ),
                                    ),
                                  ),
                                )
                              : SliverList.builder(
                                  itemCount: parcel.milestones.length,
                                  itemBuilder: (context, index) =>
                                      _MilestoneTile(
                                        milestone: parcel.milestones[index],
                                        latest: index == 0,
                                      ),
                                ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchPanel() => _TrackingPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Follow your parcel',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter the tracking number from your waybill or order details.',
          style: TextStyle(color: BagooTheme.muted, height: 1.5),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _number,
          maxLength: 64,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => _tracking.edited(),
          onSubmitted: (_) => _lookup(),
          decoration: InputDecoration(
            labelText: 'Tracking number',
            counterText: '',
            errorText: _tracking.fieldError,
            prefixIcon: const ExcludeSemantics(child: Icon(Icons.search)),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _number,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Clear tracking number',
                      onPressed: () {
                        _number.clear();
                        _tracking.edited();
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _number,
          builder: (context, value, _) => SubmitButton(
            label: 'Track parcel',
            busy: _tracking.loading,
            onPressed: value.text.trim().isEmpty ? null : _lookup,
          ),
        ),
      ],
    ),
  );

  Widget _privacyNote() => const _TrackingPanel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(Icons.shield_outlined, color: BagooTheme.muted),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Recipient details are masked for privacy. Order actions are available in Profile under My Purchases & Orders.',
            style: TextStyle(color: BagooTheme.muted, height: 1.5),
          ),
        ),
      ],
    ),
  );

  Widget _problem() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Notice(_tracking.problem!, error: true),
      if (_tracking.result != null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Showing the last confirmed lookup below. Its checked time has not changed.',
            style: TextStyle(color: BagooTheme.muted, height: 1.5),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _tracking.loading ? null : _retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ),
    ],
  );

  Widget _notFound(TrackingLookup lookup) => _TrackingPanel(
    child: Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parcel not found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SelectableText(
            lookup.number,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check the tracking number on your waybill and try again. An order number is different from a parcel tracking number.',
            style: TextStyle(color: BagooTheme.muted, height: 1.5),
          ),
        ],
      ),
    ),
  );

  Widget _resultPanels(TrackingLookup lookup, PublicParcel parcel, bool wide) {
    final time = trackingTime(lookup.observedAt);
    final checked = lookup.observedAt == null
        ? 'Checked time unavailable'
        : 'Checked $time';
    final summary = _TrackingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Waybill tracking number',
            style: TextStyle(fontSize: 12, color: BagooTheme.muted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  parcel.number,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy tracking number',
                onPressed: () => _copy(parcel.number),
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: BagooTheme.rose,
                border: Border.all(color: BagooTheme.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                parcel.statusLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$checked · Philippine time',
            style: const TextStyle(
              fontSize: 12,
              color: BagooTheme.muted,
              height: 1.5,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _tracking.loading ? null : _tracking.refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh tracking'),
            ),
          ),
          const Divider(height: 32),
          _TrackingDetail('Delivery area', parcel.deliveryArea),
          const SizedBox(height: 16),
          _TrackingDetail(
            'Estimated delivery',
            trackingTime(
              parcel.estimatedDeliveryAt,
              missing: 'Not yet scheduled',
            ),
          ),
          const SizedBox(height: 16),
          _TrackingDetail('Delivered at', trackingTime(parcel.deliveredAt)),
        ],
      ),
    );
    final recipient = _TrackingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Protected recipient',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _TrackingDetail('Name', parcel.recipientName),
          const SizedBox(height: 16),
          _TrackingDetail('Contact', parcel.recipientPhone),
        ],
      ),
    );
    if (!wide) {
      return Column(children: [summary, const SizedBox(height: 16), recipient]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: summary),
        const SizedBox(width: 16),
        Expanded(child: recipient),
      ],
    );
  }
}

class _TrackingPanel extends StatelessWidget {
  const _TrackingPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BagooTheme.border),
    ),
    child: child,
  );
}

class _TrackingDetail extends StatelessWidget {
  const _TrackingDetail(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
      ),
    ],
  );
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({required this.milestone, required this.latest});
  final TrackingMilestone milestone;
  final bool latest;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _TrackingPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              latest ? Icons.location_on_outlined : Icons.check_circle_outline,
              color: latest ? BagooTheme.strong : BagooTheme.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (latest) ...[
                  const Text(
                    'Latest recorded update',
                    style: TextStyle(
                      fontSize: 12,
                      color: BagooTheme.strong,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  milestone.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(milestone.location, style: const TextStyle(height: 1.5)),
                const SizedBox(height: 6),
                Text(
                  trackingTime(milestone.recordedAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: BagooTheme.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
