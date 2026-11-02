import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/web_session.dart';
import '../../core/foreground_refresh.dart';
import '../../core/widgets.dart';
import '../products/chat_page.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

int? _positiveId(Object? value) => value is int && value > 0 ? value : null;

bool _completeConversation(Map<String, dynamic> row, Set<int> recipientIds) {
  final rawRecipient = row['user'];
  if (rawRecipient is! Map || rawRecipient.keys.any((key) => key is! String)) {
    return false;
  }
  final recipient = Map<String, dynamic>.from(rawRecipient);
  final recipientId = _positiveId(recipient['id']);
  final name = recipient['name'];
  final role = recipient['role'];
  final avatar = recipient['avatar'];
  final rawShop = recipient['shop'];
  final shop = rawShop is Map && rawShop.keys.every((key) => key is String)
      ? Map<String, dynamic>.from(rawShop)
      : null;
  final orderId = row['order_id'];
  final preview = row['last_message'];
  final time = row['last_time'];
  final unread = row['unread_count'];
  if (recipientId == null ||
      !recipientIds.add(recipientId) ||
      name is! String ||
      name.trim().isEmpty ||
      role is! String ||
      !{'seller', 'courier'}.contains(role) ||
      avatar != null && avatar is! String ||
      rawShop != null && shop == null ||
      shop != null &&
          (_positiveId(shop['id']) == null ||
              shop['name'] is! String ||
              (shop['slug'] != null && shop['slug'] is! String) ||
              (shop['logo'] != null && shop['logo'] is! String)) ||
      orderId != null && _positiveId(orderId) == null ||
      preview is! String ||
      time is! String ||
      time.trim().isEmpty ||
      unread is! int ||
      unread < 0 ||
      row['messages'] is! List) {
    return false;
  }
  return true;
}

Map<String, dynamic> _conversationProductContext(
  Object? rawMessages,
  Map<String, dynamic> recipient,
) {
  if (recipient['role'] != 'seller' || rawMessages is! List) return const {};
  final shopId = _positiveId(mapOf(recipient['shop'])['id']);
  if (shopId == null) return const {};

  final messages = <Map<String, dynamic>>[];
  for (final rawMessage in rawMessages) {
    if (rawMessage is! Map || rawMessage.keys.any((key) => key is! String)) {
      return const {};
    }
    messages.add(Map<String, dynamic>.from(rawMessage));
  }

  Map<String, dynamic>? latestProduct;
  for (final message in messages) {
    final rawProduct = message['product'];
    if (rawProduct == null) continue;
    if (rawProduct is! Map || rawProduct.keys.any((key) => key is! String)) {
      return const {};
    }

    final product = Map<String, dynamic>.from(rawProduct);
    if (_positiveId(product['id']) == null || product['shop_id'] != shopId) {
      return const {};
    }
    latestProduct = product;
  }
  return latestProduct ?? const {};
}

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
  bool _openingConversation = false;
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

  bool get _sameIdentity =>
      widget.repository.session.identityEpoch == _identityEpoch;

  @override
  void didUpdateWidget(covariant InboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _updates.dispose();
      _page = null;
      _search.clear();
      _error = null;
      _accessLost = false;
      _openingConversation = false;
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
      final conversations = page.props['conversations'];
      final rows = mapsOf(conversations);
      if (page.component != 'Buyer/Messages' ||
          page.user?['role'] != 'buyer' ||
          _positiveId(page.user?['id']) == null ||
          conversations is! List ||
          rows.length != conversations.length ||
          _identityEpoch != widget.repository.session.identityEpoch ||
          _page != null && _page!.user?['id'] != page.user?['id']) {
        throw const BackendException(
          'Your messages are unavailable for this account.',
          status: 401,
        );
      }
      final recipientIds = <int>{};
      if (rows.any((row) => !_completeConversation(row, recipientIds))) {
        throw const BackendException(
          'The conversation list could not be confirmed.',
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
    final page = _page;
    final recipient = mapOf(conversation['user']);
    final userId = _positiveId(page?.user?['id']);
    final receiverId = _positiveId(recipient['id']);
    if (_loading ||
        _accessLost ||
        _openingConversation ||
        !_sameIdentity ||
        page == null ||
        userId == null ||
        receiverId == null) {
      return;
    }
    final shop = mapOf(recipient['shop']);
    final product = _conversationProductContext(
      conversation['messages'],
      recipient,
    );
    final orderId = _positiveId(conversation['order_id']);
    setState(() => _openingConversation = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            repository: widget.repository.buyer,
            userId: userId,
            receiverId: receiverId,
            orderId: orderId,
            conversationTitle:
                shop['name']?.toString() ??
                recipient['name']?.toString() ??
                'Conversation',
            product: product.isEmpty
                ? const {}
                : {
                    ...product,
                    'shop': {...shop, 'user_id': receiverId},
                  },
            canAttach: recipient['role'] != 'courier',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingConversation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = mapsOf(_page?.props['conversations']).where((conversation) {
      final recipient = mapOf(conversation['user']);
      return _positiveId(recipient['id']) != null &&
          '${recipient['name']} ${mapOf(recipient['shop'])['name']} ${conversation['last_message']}'
              .toLowerCase()
              .contains(_search.text.trim().toLowerCase());
    }).toList();
    return ForegroundRefresh(
      controller: _updates,
      enabled: !_accessLost,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: BagooTheme.strong,
          foregroundColor: Colors.white,
          title: const Text(
            'Messages',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
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
                        final unread = conversation['unread_count'] as int;
                        final name =
                            mapOf(recipient['shop'])['name']?.toString() ??
                            recipient['name']?.toString() ??
                            'Conversation';
                        final time =
                            conversation['last_time']?.toString() ?? '';
                        return ProfilePanel(
                          padding: 0,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              BagooTheme.panelRadius,
                            ),
                            onTap:
                                _loading || _accessLost || _openingConversation
                                ? null
                                : () => _open(conversation),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ProfileAvatar(
                                    recipient,
                                    widget.repository.session,
                                    size: 44,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${conversation['last_message'] ?? ''}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                            color: BagooTheme.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          recipient['role'] == 'courier'
                                              ? 'Courier'
                                              : 'Store',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: BagooTheme.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 64,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (time.isNotEmpty)
                                          Text(
                                            time,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.end,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: BagooTheme.muted,
                                            ),
                                          ),
                                        if (unread > 0) ...[
                                          const SizedBox(height: 8),
                                          Semantics(
                                            label: '$unread unread messages',
                                            excludeSemantics: true,
                                            child: Badge(
                                              backgroundColor:
                                                  BagooTheme.strong,
                                              textStyle: const TextStyle(
                                                fontFamily: 'Plus Jakarta Sans',
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              label: Text(
                                                unread > 99 ? '99+' : '$unread',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
