import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../engagement/buyer_destination_router.dart';
import '../engagement/engagement_repository.dart';
import '../home/search_controller.dart';
import 'push_notifications.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.repository,
    required this.ownerId,
    this.initialNotificationId,
    this.onSearch,
    this.onProfileSection,
    this.onSummaryChanged,
  });

  final BuyerRepository repository;
  final int ownerId;
  final String? initialNotificationId;
  final ValueChanged<SearchFilters>? onSearch;
  final ValueChanged<String>? onProfileSection;
  final ValueChanged<int>? onSummaryChanged;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  WebPage? _page;
  String _filter = 'all';
  int _number = 1;
  int _generation = 0;
  String? _error;
  String? _reading;
  bool _loading = true;

  BuyerEngagementRepository get _repository =>
      BuyerEngagementRepository(widget.repository);
  Map<String, dynamic> get _paginator => mapOf(_page?.props['notices']);
  List<Map<String, dynamic>> get _notices => mapsOf(_paginator['data']);
  Map<String, dynamic> get _snapshot => mapOf(_page?.props['readSnapshot']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load({String? filter, int page = 1}) async {
    final nextFilter = filter ?? _filter;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (nextFilter != _filter) {
        _page = null;
      }
      _filter = nextFilter;
    });
    try {
      final result = await _repository.notifications(
        filter: nextFilter,
        page: page,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      if (result.user?['id'] != widget.ownerId) {
        throw const BackendException(
          'Your account changed. Sign in again to view notifications.',
          status: 401,
        );
      }
      setState(() {
        _page = result;
        _number = (mapOf(result.props['notices'])['current_page'] as num)
            .toInt();
      });
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshSummary() async {
    try {
      final response = await _repository.notificationPreview();
      final summary = mapOf(response['summary']);
      final count = (summary['unread'] as num).toInt();
      if (mounted) widget.onSummaryChanged?.call(count);
    } on BackendException {
      // The inbox stays useful when the optional toolbar badge is unavailable.
    }
  }

  Future<bool> _markRead(String id) async {
    if (_reading != null) return false;
    setState(() {
      _reading = id;
      _error = null;
    });
    try {
      await _repository.markNotificationRead(id);
      await _load(page: _number);
      await _refreshSummary();
      return true;
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => _reading = null);
    }
  }

  Future<void> _markAllRead() async {
    final snapshot = _snapshot['id']?.toString();
    if (_reading != null || snapshot == null || snapshot.isEmpty) return;
    setState(() {
      _reading = 'all';
      _error = null;
    });
    try {
      final count = await _repository.markNotificationSnapshotRead(snapshot);
      if (mounted) widget.onSummaryChanged?.call(count);
      await _load(page: 1);
      await _refreshSummary();
    } on BackendException catch (e) {
      final message = e.fields['snapshot'] ?? e.message;
      await _load(page: 1);
      await _refreshSummary();
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _reading = null);
    }
  }

  Future<void> _openNotice(Map<String, dynamic> notice) async {
    final id = notice['id']?.toString() ?? '';
    if (_reading != null || id.isEmpty) return;
    if (notice['read_at'] == null && !await _markRead(id)) return;
    if (!mounted) return;
    final href = notice['href']?.toString();
    if (href == null || href.isEmpty) {
      _showMessage('This update has no linked buyer screen.');
      return;
    }
    try {
      await BuyerDestinationRouter.openHref(
        context,
        widget.repository,
        href,
        onSearch: widget.onSearch,
        onProfileSection: widget.onProfileSection,
        closeForTabDestination: true,
      );
    } on BackendException catch (e) {
      if (mounted) _showMessage(e.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        IconButton(
          tooltip: 'Refresh notifications',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return RefreshIndicator(
            onRefresh: _load,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    wide ? 28 : 16,
                    20,
                    wide ? 28 : 16,
                    32,
                  ),
                  children: [
                    _heading(),
                    const SizedBox(height: 12),
                    _PushNotificationControl(
                      repository: widget.repository,
                      ownerId: widget.ownerId,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final option in const {
                              'all': 'All',
                              'unread': 'Unread',
                            }.entries)
                              ChoiceChip(
                                label: Text(option.value),
                                selected: _filter == option.key,
                                onSelected: _loading || _reading != null
                                    ? null
                                    : (_) => _load(filter: option.key),
                              ),
                          ],
                        ),
                        if (_snapshot.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _loading || _reading != null
                                ? null
                                : _markAllRead,
                            icon: _reading == 'all'
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.done_all),
                            label: Text(
                              'Mark all as read (${_snapshot['count'] ?? 0})',
                            ),
                          ),
                      ],
                    ),
                    if (_loading && _page == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 56),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_error != null) _errorPanel(),
                    if (_page != null && _page!.props['available'] != true)
                      const _UnavailableNotifications(),
                    if (_page != null &&
                        _page!.props['available'] == true &&
                        !_loading &&
                        _notices.isEmpty)
                      _EmptyNotifications(unread: _filter == 'unread'),
                    if (_page != null && _notices.isNotEmpty) ...[
                      if (_loading) const LinearProgressIndicator(),
                      for (final notice in _notices)
                        _NotificationCard(
                          notice: notice,
                          highlighted:
                              notice['id'] == widget.initialNotificationId,
                          busy: _reading == notice['id'],
                          anyBusy: _reading != null,
                          onOpen: () => _openNotice(notice),
                          onMarkRead: () =>
                              _markRead(notice['id']?.toString() ?? ''),
                        ),
                      _Paginator(
                        current: _number,
                        last: (_paginator['last_page'] as num?)?.toInt() ?? 1,
                        busy: _loading || _reading != null,
                        onPage: (page) => _load(page: page),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _heading() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BagooTheme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Bagoo updates',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Order, delivery, and account updates for your buyer account.',
          style: TextStyle(height: 1.5, color: BagooTheme.muted),
        ),
        if (_page != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${mapOf(_page!.props['notificationSummary'])['unread'] ?? _snapshot['count'] ?? 0} unread updates',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: BagooTheme.strong,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _errorPanel() => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF1B7C5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Notice(_error!, error: true),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
            if (_error!.toLowerCase().contains('sign in') ||
                _error!.toLowerCase().contains('session'))
              OutlinedButton(
                onPressed: () => BuyerActions.login(context),
                child: const Text('Sign in'),
              ),
          ],
        ),
      ],
    ),
  );
}

class _PushNotificationControl extends StatefulWidget {
  const _PushNotificationControl({
    required this.repository,
    required this.ownerId,
  });
  final BuyerRepository repository;
  final int ownerId;

  @override
  State<_PushNotificationControl> createState() =>
      _PushNotificationControlState();
}

class _PushNotificationControlState extends State<_PushNotificationControl> {
  final _push = PushNotifications.instance;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _push.registrationRevision.addListener(_changed);
    unawaited(_sync());
  }

  @override
  void dispose() {
    _push.registrationRevision.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _sync() async {
    await _push.syncIfAuthorized(widget.repository, widget.ownerId);
    if (mounted) setState(() {});
  }

  Future<void> _enable() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _push.enable(widget.repository, widget.ownerId);
    } on BackendException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _push.disable(widget.repository, widget.ownerId);
    } on BackendException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _push.isEnabledFor(widget.repository);
    final configured = _push.isConfigured;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BagooTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                color: BagooTheme.crimson,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  enabled
                      ? 'Push alerts are on'
                      : 'Get Bagoo alerts on this device',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (configured)
                TextButton(
                  onPressed: _busy
                      ? null
                      : enabled
                      ? _disable
                      : _enable,
                  child: Text(
                    _busy
                        ? 'Please wait…'
                        : enabled
                        ? 'Turn off'
                        : 'Turn on',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            configured
                ? 'Receive a general alert when Bagoo adds a new update. Open Notifications to view the details securely.'
                : 'Push alerts are not configured for this build. Your updates still appear here.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: BagooTheme.muted,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Notice(_error!, error: true),
          ],
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notice,
    required this.highlighted,
    required this.busy,
    required this.anyBusy,
    required this.onOpen,
    required this.onMarkRead,
  });

  final Map<String, dynamic> notice;
  final bool highlighted;
  final bool busy, anyBusy;
  final VoidCallback onOpen, onMarkRead;

  @override
  Widget build(BuildContext context) {
    final data = mapOf(notice['data']);
    final unread = notice['read_at'] == null;
    final hubName = data['hub_name']?.toString();
    final body = data['body']?.toString();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: unread ? const Color(0xFFFFF6F8) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? BagooTheme.crimson
              : unread
              ? const Color(0xFFF1B7C5)
              : BagooTheme.border,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlighted) ...[
            const Text(
              'Opened from your Bagoo alert',
              style: TextStyle(
                color: BagooTheme.strong,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unread) ...[
                Semantics(
                  label: 'Unread',
                  child: const ExcludeSemantics(
                    child: Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: Icon(
                        Icons.circle,
                        size: 9,
                        color: BagooTheme.strong,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  data['title']?.toString() ?? 'Account update',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (data['order_number'] is String) ...[
            const SizedBox(height: 5),
            Text(
              'Order ${data['order_number']}',
              style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
            ),
          ],
          if (body != null && body.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(height: 1.5)),
          ],
          if (hubName != null && hubName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BagooTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hubName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (data['hub_address'] is String)
                    Text(data['hub_address'].toString()),
                  if (data['operating_hours'] is String)
                    Text(data['operating_hours'].toString()),
                  if (data['expires_at'] is String)
                    Text(
                      'Holding period ends ${_manilaDate(data['expires_at'])}',
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                _manilaDate(notice['created_at']),
                style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
              ),
              if (notice['href'] is String &&
                  notice['href'].toString().isNotEmpty)
                FilledButton.icon(
                  onPressed: anyBusy ? null : onOpen,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View update'),
                ),
              if (unread)
                OutlinedButton.icon(
                  onPressed: anyBusy ? null : onMarkRead,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done),
                  label: const Text('Mark read'),
                )
              else
                const Text(
                  'Read',
                  style: TextStyle(fontSize: 12, color: BagooTheme.muted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications({required this.unread});

  final bool unread;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BagooTheme.border),
    ),
    child: Column(
      children: [
        const Icon(Icons.notifications_none, size: 38, color: BagooTheme.muted),
        const SizedBox(height: 12),
        Text(
          unread ? 'You have no unread updates' : 'No notifications yet',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Order and account updates will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5, color: BagooTheme.muted),
        ),
      ],
    ),
  );
}

class _UnavailableNotifications extends StatelessWidget {
  const _UnavailableNotifications();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BagooTheme.border),
    ),
    child: const Column(
      children: [
        Icon(
          Icons.notifications_off_outlined,
          size: 32,
          color: BagooTheme.muted,
        ),
        SizedBox(height: 12),
        Text(
          'Notifications are temporarily unavailable',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 6),
        Text(
          'Your saved orders and account decisions remain available in their usual sections.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5, color: BagooTheme.muted),
        ),
      ],
    ),
  );
}

class _Paginator extends StatelessWidget {
  const _Paginator({
    required this.current,
    required this.last,
    required this.busy,
    required this.onPage,
  });

  final int current, last;
  final bool busy;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: busy || current <= 1 ? null : () => onPage(current - 1),
          icon: const Icon(Icons.chevron_left),
          label: const Text('Previous'),
        ),
        Text('Page $current of $last'),
        OutlinedButton.icon(
          onPressed: busy || current >= last ? null : () => onPage(current + 1),
          icon: const Icon(Icons.chevron_right),
          label: const Text('Next'),
        ),
      ],
    ),
  );
}

String _manilaDate(dynamic raw) {
  final parsed = DateTime.tryParse(raw?.toString() ?? '');
  if (parsed == null) return 'Date unavailable';
  final date = parsed.toUtc().add(const Duration(hours: 8));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour < 12 ? 'AM' : 'PM';
  return '${date.day} ${months[date.month - 1]} ${date.year}, $hour:$minute $suffix (Manila)';
}
