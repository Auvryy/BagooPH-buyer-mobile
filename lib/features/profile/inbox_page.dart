import 'package:flutter/material.dart';

import '../../core/web_session.dart';
import '../../core/foreground_refresh.dart';
import '../../core/widgets.dart';
import '../products/chat_page.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key, required this.repository});
  final ProfileRepository repository;
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  WebPage? _page;
  String? _error;
  bool _loading = true;
  bool _accessLost = false;
  late int _identityEpoch;
  late ForegroundRead _updates;
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _configure();
  }

  void _configure() {
    _identityEpoch = widget.repository.session.identityEpoch;
    _updates = ForegroundRead(read: _load);
  }

  @override
  void didUpdateWidget(covariant InboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _updates.dispose();
      _page = null;
      _search.clear();
      _error = null;
      _accessLost = false;
      _loading = true;
      _configure();
    }
  }

  @override
  void dispose() {
    _updates.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<ReadOutcome> _load(ReadTicket ticket) async {
    try {
      if (_identityEpoch != widget.repository.session.identityEpoch) {
        throw const BackendException(
          'Your account changed. Reopen your inbox after signing in.',
          status: 401,
        );
      }
      final page = await widget.repository.buyer.document('/buyer/messages');
      if (!mounted || !ticket.isCurrent) return ReadOutcome.success;
      widget.repository.buyer.requireNoErrors(page);
      if (page.component != 'Buyer/Messages' ||
          page.user?['role'] != 'buyer' ||
          page.user?['id'] is! num ||
          page.props['conversations'] is! List ||
          _identityEpoch != widget.repository.session.identityEpoch ||
          _page != null && _page!.user?['id'] != page.user?['id']) {
        throw const BackendException(
          'Your messages are unavailable for this account.',
          status: 401,
        );
      }
      setState(() {
        _page = page;
        _error = null;
        _loading = false;
      });
      return ReadOutcome.success;
    } on BackendException catch (e) {
      if (!mounted || !ticket.isCurrent) return ReadOutcome.success;
      setState(() {
        _accessLost =
            [401, 403, 419].contains(e.status) ||
            _identityEpoch != widget.repository.session.identityEpoch;
        _error = _accessLost
            ? e.message
            : 'Inbox could not update. Retrying automatically. ${e.message}';
        if (_accessLost) {
          _page = null;
          _search.clear();
        }
        _loading = false;
      });
      return _accessLost ? ReadOutcome.stop : ReadOutcome.retry;
    } catch (_) {
      if (mounted && ticket.isCurrent) {
        setState(() {
          _error = 'Inbox could not update. Retrying automatically.';
          _loading = false;
        });
      }
      return ReadOutcome.retry;
    }
  }

  Future<void> _open(Map<String, dynamic> conversation) async {
    final recipient = mapOf(conversation['user']);
    final recent = mapsOf(conversation['messages'])
        .where((m) => m['product'] != null)
        .lastOrNull;
    final product = mapOf(recent?['product']);
    final shop = mapOf(recipient['shop']);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          repository: widget.repository.buyer,
          userId: (_page!.user!['id'] as num).toInt(),
          receiverId: (recipient['id'] as num).toInt(),
          orderId: (conversation['order_id'] as num?)?.toInt(),
          conversationTitle:
              shop['name']?.toString() ??
              recipient['name']?.toString() ??
              'Conversation',
          product: product.isEmpty
              ? const {}
              : {
                  ...product,
                  'shop': {...shop, 'user_id': recipient['id']},
                },
          canAttach: recipient['role'] != 'courier',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = mapsOf(_page?.props['conversations']).where((conversation) {
      final recipient = mapOf(conversation['user']);
      return recipient['id'] is num &&
          '${recipient['name']} ${mapOf(recipient['shop'])['name']} ${conversation['last_message']}'
              .toLowerCase()
              .contains(_search.text.trim().toLowerCase());
    }).toList();
    return ForegroundRefresh(
      controller: _updates,
      enabled: !_accessLost,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Store & Courier Messages'),
          actions: [
            IconButton(
              tooltip: 'Refresh inbox',
              onPressed: _loading || _accessLost ? null : _updates.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Search conversations',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  if (_loading) const LinearProgressIndicator(),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            children: [
                              if (_error != null) ...[
                                Notice(_error!, error: true),
                                if (!_accessLost)
                                  TextButton(
                                    onPressed: _loading
                                        ? null
                                        : _updates.refresh,
                                    child: const Text('Try again'),
                                  ),
                              ],
                              if (!_loading && rows.isEmpty && _error == null)
                                const ProfilePanel(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 40),
                                    child: Text(
                                      'No conversations found. Start a product inquiry from a product page.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(height: 1.7),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }
                        final conversation = rows[index - 1];
                        final recipient = mapOf(conversation['user']);
                        return ProfilePanel(
                          padding: 8,
                          child: ListTile(
                            leading: ProfileAvatar(
                              recipient,
                              widget.repository.session,
                              size: 44,
                            ),
                            title: Text(
                              mapOf(recipient['shop'])['name']?.toString() ??
                                  recipient['name'].toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${conversation['last_message'] ?? ''}\n${recipient['role'] == 'courier' ? 'Courier' : 'Store'} · ${conversation['last_time'] ?? ''}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing:
                                (conversation['unread_count'] as num? ?? 0) > 0
                                ? Badge(
                                    label: Text(
                                      conversation['unread_count'].toString(),
                                    ),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: _loading ? null : () => _open(conversation),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
