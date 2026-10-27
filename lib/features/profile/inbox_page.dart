import 'package:flutter/material.dart';

import '../../core/web_session.dart';
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
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.buyer.document('/buyer/messages');
      widget.repository.buyer.requireNoErrors(page);
      if (page.component != 'Buyer/Messages' ||
          page.user?['role'] != 'buyer' ||
          page.props['conversations'] is! List) {
        throw const BackendException(
          'Your messages are unavailable for this account.',
        );
      }
      if (mounted) setState(() => _page = page);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
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
    if (mounted) await _load();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store & Courier Messages'),
        actions: [
          IconButton(
            tooltip: 'Refresh inbox',
            onPressed: _loading ? null : _load,
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
                              TextButton(
                                onPressed: _loading ? null : _load,
                                child: const Text('Try again'),
                              ),
                            ],
                            if (!_loading && rows.isEmpty)
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
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
    );
  }
}
