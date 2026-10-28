import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/viewport_visibility.dart';
import '../engagement/engagement_repository.dart';
import '../products/product_widgets.dart';

class NotificationPreview extends StatefulWidget {
  const NotificationPreview({
    super.key,
    required this.repository,
    required this.ownerId,
    required this.isCurrentOwner,
    this.onSummaryChanged,
  });
  final BuyerRepository repository;
  final int ownerId;
  final bool Function() isCurrentOwner;
  final ValueChanged<int>? onSummaryChanged;
  @override
  State<NotificationPreview> createState() => _NotificationPreviewState();
}

class _NotificationPreviewState extends State<NotificationPreview>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _notices = [];
  final _seen = <String>{};
  bool _busy = false;
  String? _error;
  int _generation = 0;
  late int _epoch;
  bool get _current =>
      mounted &&
      widget.isCurrentOwner() &&
      _epoch == widget.repository.session.identityEpoch;
  List<String> get _displayed => [
    for (final notice in _notices)
      if (notice['id'] is String &&
          _seen.contains(notice['id']) &&
          notice['read_at'] == null)
        notice['id'] as String,
  ];
  BuyerEngagementRepository get _repository =>
      BuyerEngagementRepository(widget.repository);
  @override
  void initState() {
    super.initState();
    _epoch = widget.repository.session.identityEpoch;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(NotificationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.repository != widget.repository) {
      _epoch = widget.repository.session.identityEpoch;
      _notices = [];
      _seen.clear();
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  void _clear() {
    _notices = [];
    _seen.clear();
    _error = 'Your account changed. Open notifications again after signing in.';
  }

  Future<void> _load() async {
    if (!_current) {
      if (mounted) setState(_clear);
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _repository.notificationPreview();
      if (!mounted || generation != _generation) return;
      if (!_current) {
        setState(_clear);
        return;
      }
      setState(() {
        _notices = mapsOf(data['notices']).take(6).toList();
      });
      widget.onSummaryChanged?.call(
        (mapOf(data['summary'])['unread'] as num).toInt(),
      );
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e.message;
          if ([401, 403, 419].contains(e.status)) _notices = [];
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _markDisplayed() async {
    final ids = List<String>.unmodifiable(_displayed);
    if (_busy || !_current || ids.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final unread = await _repository.markDisplayedNotifications(ids);
      if (!_current) {
        if (mounted) setState(_clear);
        return;
      }
      widget.onSummaryChanged?.call(unread);
      await _load();
    } on BackendException catch (e) {
      if (_current) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Recent updates',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              IconButton(
                tooltip: 'Close notification preview',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) Notice(_error!, error: true),
              if (!_busy && _notices.isEmpty && _error == null)
                const Text('No notifications yet.'),
              for (final notice in _notices)
                ViewportVisibility(
                  key: ValueKey('$_generation:${notice['id']}'),
                  onVisibility: (ratio) {
                    final id = notice['id'];
                    if (_current &&
                        ratio > 0 &&
                        id is String &&
                        !_seen.contains(id)) {
                      setState(() => _seen.add(id));
                    }
                  },
                  child: ProductPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mapOf(notice['data'])['title']?.toString() ??
                              'Bagoo update',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            height: 1.7,
                          ),
                        ),
                        if (mapOf(notice['data'])['body'] is String)
                          Text(
                            mapOf(notice['data'])['body'],
                            style: const TextStyle(height: 1.7),
                          ),
                        Text(
                          readableDateTime(notice['created_at']),
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          notice['read_at'] == null
                              ? 'Unread'
                              : 'Read ${readableDateTime(notice['read_at'])}',
                          style: const TextStyle(fontSize: 12, height: 1.7),
                        ),
                        if (notice['href'] is String)
                          TextButton(
                            onPressed: _busy || !_current
                                ? null
                                : () => Navigator.pop(
                                    context,
                                    <String, dynamic>{'notice': notice},
                                  ),
                            child: const Text('View update'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_error != null)
                TextButton(
                  onPressed: _busy || !_current ? null : _load,
                  child: const Text('Retry preview'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _busy || !_current || _displayed.isEmpty
                    ? null
                    : _markDisplayed,
                child: Text('Mark displayed as read (${_displayed.length})'),
              ),
              FilledButton(
                onPressed: _busy || !_current
                    ? null
                    : () => Navigator.pop(context, <String, dynamic>{
                        'all': true,
                      }),
                child: const Text('View all notifications'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
