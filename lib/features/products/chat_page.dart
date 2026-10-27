import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/file_selection.dart';
import '../../core/uploads.dart';
import 'product_widgets.dart';

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
  String? _error;
  String? _intent;
  String? _intentText;
  UploadPart? _attachment;
  int get _receiver =>
      widget.receiverId ??
      (mapOf(widget.product['shop'])['user_id'] as num?)?.toInt() ??
      0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_sending) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await widget.repository.messages(_receiver);
      if (mounted) {
        setState(() => _messages = messages);
        _bottom();
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e.status == 401 || e.status == 419) _messages = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });
  Future<void> _send() async {
    if (_sending || _loading) {
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty && _attachment == null || text.length > 1000) {
      _failure('Enter a message of up to 1,000 characters.');
      return;
    }
    if (_intentText != text || _intent == null) {
      _intentText = text;
      _intent = requestKey();
    }
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
      if (!mounted) {
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
      if (mounted) {
        if (e.status == 401 || e.status == 419) {
          setState(() => _messages = []);
        }
        _failure(e.fields.isEmpty ? e.message : e.fields.values.join('\n'));
      }
    } finally {
      if (mounted) {
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

  Future<void> _photo() async {
    if (_sending || !widget.canAttach) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final photo = await pickUpload('attachment', imageOnly: true);
      if (photo != null && mounted) {
        setState(() {
          _attachment = photo;
          _intent = null;
          _intentText = null;
        });
      }
    } on BackendException catch (e) {
      _failure(e.message);
    } catch (_) {
      if (mounted) {
        _failure('The photo picker could not open. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
          onPressed: _loading || _sending ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              if (widget.product.isNotEmpty &&
                  MediaQuery.viewInsetsOf(context).bottom == 0)
                ListTile(
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: Text(
                    widget.product['name'].toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Product inquiry',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              if (_loading) const LinearProgressIndicator(),
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
                          if (_messages.isEmpty && !_loading)
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
                              Text(
                                mapOf(message['product'])['name']?.toString() ??
                                    '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            Text(
                              message['message']?.toString() ?? '',
                              style: const TextStyle(height: 1.6),
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
              if (_attachment != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        onPressed: _sending || _loading ? null : _photo,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        enabled: !_sending,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          labelText: 'Message',
                          counterText: '',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send message',
                      onPressed: _sending || _loading ? null : _send,
                      icon: Icon(
                        _sending ? Icons.hourglass_top : Icons.send_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
