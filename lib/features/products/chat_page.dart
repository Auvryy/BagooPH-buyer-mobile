import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/foreground_refresh.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/file_selection.dart';
import '../../core/uploads.dart';
import 'product_widgets.dart';
import 'product_page.dart';
import '../home/product_card.dart';

String requestKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.repository,
    this.product = const {},
    required this.userId,
    this.receiverId,
    this.orderId,
    this.conversationTitle,
    this.canAttach = true,
  });
  final BuyerRepository repository;
  final Map<String, dynamic> product;
  final int userId;
  final int? receiverId, orderId;
  final String? conversationTitle;
  final bool canAttach;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _accessLost = false;
  String? _error;
  String? _updateError;
  String? _intent;
  String? _intentText;
  UploadPart? _attachment;
  late ForegroundRead _updates;
  late int _identityEpoch;
  int _scope = 0;
  int get _receiver =>
      widget.receiverId ??
      (mapOf(widget.product['shop'])['user_id'] as num?)?.toInt() ??
      0;
  @override
  void initState() {
    super.initState();
    _configureUpdates();
  }

  void _configureUpdates() {
    _identityEpoch = widget.repository.session.identityEpoch;
    _updates = ForegroundRead(
      read: _load,
      interval: const Duration(seconds: 8),
    );
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.userId != widget.userId ||
        oldWidget.receiverId != widget.receiverId ||
        oldWidget.product['id'] != widget.product['id'] ||
        mapOf(oldWidget.product['shop'])['user_id'] !=
            mapOf(widget.product['shop'])['user_id']) {
      _updates.dispose();
      _scope++;
      _messages = [];
      _text.clear();
      _attachment = null;
      _intent = _intentText = _error = _updateError = null;
      _accessLost = _sending = false;
      _loading = true;
      _configureUpdates();
    }
  }

  bool _current(int scope) => mounted && scope == _scope;
  bool get _sameIdentity =>
      widget.repository.session.identityEpoch == _identityEpoch;

  void _loseAccess(String message) {
    if (!mounted) return;
    _updates.setActive(false);
    _scope++;
    setState(() {
      _accessLost = true;
      _messages = [];
      _text.clear();
      _attachment = null;
      _intent = _intentText = null;
      _error = null;
      _updateError = message;
      _loading = _sending = false;
    });
  }

  Future<ReadOutcome> _load(ReadTicket ticket) async {
    if (!_sameIdentity) {
      _loseAccess(
        'Your account changed. Reopen this conversation after signing in.',
      );
      return ReadOutcome.stop;
    }
    try {
      final messages = await widget.repository.messages(_receiver);
      if (!mounted || !ticket.isCurrent) return ReadOutcome.success;
      if (!_sameIdentity ||
          messages.any(
            (m) =>
                m['id'] is! num ||
                !((m['sender_id'] == widget.userId &&
                        m['receiver_id'] == _receiver) ||
                    (m['sender_id'] == _receiver &&
                        m['receiver_id'] == widget.userId)),
          )) {
        throw const BackendException(
          'This conversation could not be confirmed for your account.',
          status: 401,
        );
      }
      final known = _messages.map((m) => m['id']).toSet();
      final added = messages.any((m) => !known.contains(m['id']));
      final follow = !_scroll.hasClients || _scroll.position.extentAfter < 80;
      setState(() {
        _messages = {for (final m in messages) m['id']: m}.values.toList();
        _updateError = null;
        _loading = false;
      });
      if (added && follow) _bottom();
      return ReadOutcome.success;
    } on BackendException catch (e) {
      if (!mounted || !ticket.isCurrent) return ReadOutcome.success;
      if (!_sameIdentity || [401, 403, 404, 419].contains(e.status)) {
        _loseAccess(e.message);
        return ReadOutcome.stop;
      }
      setState(() {
        _updateError =
            'Messages could not update. Retrying automatically. ${e.message}';
        _loading = false;
      });
      return ReadOutcome.retry;
    } catch (_) {
      if (mounted && ticket.isCurrent) {
        setState(() {
          _updateError = 'Messages could not update. Retrying automatically.';
          _loading = false;
        });
      }
      return ReadOutcome.retry;
    }
  }

  void _bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });
  Future<void> _send() async {
    if (_sending || _loading || _accessLost) {
      return;
    }
    if (!_sameIdentity) {
      _loseAccess(
        'Your account changed. Reopen this conversation after signing in.',
      );
      return;
    }
    final scope = _scope;
    final text = _text.text.trim();
    if (text.isEmpty && _attachment == null || text.length > 1000) {
      _failure('Enter a message of up to 1,000 characters.');
      return;
    }
    if (_intentText != text || _intent == null) {
      _intentText = text;
      _intent = requestKey();
    }
    _updates.setActive(false);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final message = await widget.repository.sendMessage({
        'receiver_id': _receiver,
        'shop_id':
            widget.product['shop_id'] ?? mapOf(widget.product['shop'])['id'],
        'product_id': widget.product['id'],
        'order_id': widget.orderId,
        'message': text,
        'request_key': _intent,
      }, files: _attachment == null ? null : [_attachment!]);
      if (!_current(scope)) {
        return;
      }
      if (!_sameIdentity) {
        _loseAccess(
          'Your account changed. Reopen this conversation after signing in.',
        );
        return;
      }
      setState(() {
        if (!_messages.any((m) => m['id'] == message['id'])) {
          _messages.add(message);
        }
        _text.clear();
        _intent = null;
        _intentText = null;
        _attachment = null;
      });
      _bottom();
    } on BackendException catch (e) {
      if (_current(scope)) {
        if (!_sameIdentity || [401, 403, 419].contains(e.status)) {
          _loseAccess(e.message);
          return;
        }
        _failure(e.fields.isEmpty ? e.message : e.fields.values.join('\n'));
      }
    } finally {
      if (_current(scope)) {
        setState(() => _sending = false);
      }
    }
  }

  void _failure(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _draftQuestion(String question) {
    if (_sending || _loading || _accessLost) return;
    final current = _text.text.trim();
    final draft = current.isEmpty ? question : '$current\n$question';
    if (draft.length > 1000) {
      _failure('Your draft is full. Edit it before adding a question.');
      return;
    }
    setState(() {
      _text.text = draft;
      _text.selection = TextSelection.collapsed(offset: draft.length);
      _intent = null;
      _intentText = null;
    });
  }

  Future<void> _photo() async {
    if (_sending || _accessLost || !widget.canAttach) return;
    final scope = _scope;
    _updates.setActive(false);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final photo = await pickUpload('attachment', imageOnly: true);
      if (photo != null && _current(scope) && _sameIdentity) {
        setState(() {
          _attachment = photo;
          _intent = null;
          _intentText = null;
        });
      }
    } on BackendException catch (e) {
      if (_current(scope)) _failure(e.message);
    } catch (_) {
      if (_current(scope)) {
        _failure('The photo picker could not open. Try again.');
      }
    } finally {
      if (_current(scope)) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _scope++;
    _updates.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ForegroundRefresh(
    controller: _updates,
    enabled: !_sending && !_accessLost,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.conversationTitle ??
              mapOf(widget.product['shop'])['name']?.toString() ??
              'Shop chat',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh conversation',
            onPressed: _loading || _sending || _accessLost
                ? null
                : _updates.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: LayoutBuilder(
              builder: (context, box) => Column(
                children: [
                  if (widget.product.isNotEmpty &&
                      box.maxHeight > 500 &&
                      MediaQuery.viewInsetsOf(context).bottom == 0)
                    ChatProductCard(
                      repository: widget.repository,
                      product: widget.product,
                    ),
                  if (_loading) const LinearProgressIndicator(),
                  if (_updateError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Notice(_updateError!, error: true),
                          if (!_accessLost)
                            TextButton(
                              onPressed: _updates.refresh,
                              child: const Text('Refresh messages'),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + 1,
                      itemBuilder: (_, index) {
                        if (index == 0) {
                          return Column(
                            children: [
                              if (_error != null) Notice(_error!, error: true),
                              if (_messages.isEmpty &&
                                  !_loading &&
                                  _updateError == null)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Start a conversation.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                            ],
                          );
                        }
                        final message = _messages[index - 1];
                        final mine = message['sender_id'] == widget.userId;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 440),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: mine ? BagooTheme.rose : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: BagooTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (message['product'] != null)
                                  ChatProductCard(
                                    repository: widget.repository,
                                    product: mapOf(message['product']),
                                  ),
                                Text(
                                  message['message']?.toString() ?? '',
                                  style: const TextStyle(height: 1.6),
                                ),
                                Text(
                                  readableDateTime(message['created_at']),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.7,
                                    color: BagooTheme.muted,
                                  ),
                                ),
                                if (message['attachment_url'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: SizedBox(
                                      width: 220,
                                      height: 180,
                                      child: InkWell(
                                        onTap: () => viewImage(
                                          context,
                                          widget.repository.session,
                                          '/chat/attachments/${message['id']}',
                                          'Chat photo',
                                          private: true,
                                        ),
                                        child: Semantics(
                                          label: 'Open chat photo',
                                          button: true,
                                          child: RemoteImage(
                                            uri: widget.repository.session.resolve(
                                              '/chat/attachments/${message['id']}',
                                            ),
                                            headers: widget.repository.session
                                                .imageHeaders(
                                                  '/chat/attachments/${message['id']}',
                                                ),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: box.maxHeight * .65),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.product.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  TextButton(
                                    onPressed:
                                        _sending || _loading || _accessLost
                                        ? null
                                        : () => _draftQuestion(
                                            'Hello, I would like to ask about ${widget.product['name']}.',
                                          ),
                                    child: const Text(
                                      'Write a product inquiry',
                                    ),
                                  ),
                                  for (final question in const [
                                    'Is this available?',
                                    'How long does shipping take?',
                                    'What sizes are available?',
                                  ])
                                    ActionChip(
                                      label: Text(question),
                                      onPressed:
                                          _sending || _loading || _accessLost
                                          ? null
                                          : () => _draftQuestion(question),
                                    ),
                                ],
                              ),
                            ),
                          if (_attachment != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                children: [
                                  SizedBox.square(
                                    dimension: 44,
                                    child: Image.memory(
                                      _attachment!.bytes,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.image_outlined),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _attachment!.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove selected photo',
                                    onPressed: _sending
                                        ? null
                                        : () => setState(() {
                                            _attachment = null;
                                            _intent = null;
                                            _intentText = null;
                                          }),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (widget.canAttach)
                                  IconButton(
                                    tooltip: 'Attach a photo',
                                    onPressed:
                                        _sending || _loading || _accessLost
                                        ? null
                                        : _photo,
                                    icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                    ),
                                  ),
                                Expanded(
                                  child: TextField(
                                    controller: _text,
                                    enabled: !_sending && !_accessLost,
                                    minLines: 1,
                                    maxLines: 4,
                                    maxLength: 1000,
                                    decoration: const InputDecoration(
                                      labelText: 'Message',
                                      counterText: '',
                                    ),
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  tooltip: 'Send message',
                                  onPressed: _sending || _loading || _accessLost
                                      ? null
                                      : _send,
                                  icon: Icon(
                                    _sending
                                        ? Icons.hourglass_top
                                        : Icons.send_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ChatProductCard extends StatelessWidget {
  const ChatProductCard({
    super.key,
    required this.repository,
    required this.product,
  });
  final BuyerRepository repository;
  final Map<String, dynamic> product;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: SizedBox.square(
        dimension: 48,
        child: RemoteImage(
          uri: imageUri(repository.session, product['featured_image']),
        ),
      ),
      title: Text(
        product['name']?.toString() ?? 'Product',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: product['price'] == null
          ? null
          : Text(pesos(product['price']), style: const TextStyle(fontSize: 12)),
      trailing: product['slug'] is String
          ? const Icon(Icons.open_in_new, size: 18)
          : null,
      onTap: product['slug'] is String
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ProductPage(repository: repository, slug: product['slug']),
              ),
            )
          : null,
    ),
  );
}
