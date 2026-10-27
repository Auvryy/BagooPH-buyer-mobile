import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/chat_page.dart';
import 'support_repository.dart';

class SupportAssistantPage extends StatefulWidget {
  const SupportAssistantPage({
    super.key,
    required this.repository,
    required this.user,
    required this.available,
  });

  final BuyerRepository repository;
  final Map<String, dynamic> user;
  final bool available;

  @override
  State<SupportAssistantPage> createState() => _SupportAssistantPageState();
}

class _SupportAssistantPageState extends State<SupportAssistantPage> {
  final _message = TextEditingController();
  final _orderNumber = TextEditingController();
  final _scroll = ScrollController();
  late final SupportAssistantRepository _support;
  final List<_SupportMessage> _messages = [
    const _SupportMessage(
      assistant: true,
      text: 'Hi! I can help with Bagoo shopping, checkout, orders, payments, delivery, and returns.',
    ),
  ];
  List<String> _suggestions = const [
    'Where is my latest order?',
    'How do I request a return?',
    'Why can’t I check out?',
  ];
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _support = SupportAssistantRepository(widget.repository);
  }

  @override
  void dispose() {
    _message.dispose();
    _orderNumber.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? question]) async {
    if (_sending || !widget.available) return;
    final text = (question ?? _message.text).trim();
    if (text.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _sending = true;
      _error = null;
      _messages.add(_SupportMessage(assistant: false, text: text));
      _suggestions = const [];
    });
    _scrollToBottom();
    try {
      final answer = await _support.ask(text, orderNumber: _orderNumber.text);
      if (!mounted) return;
      setState(() {
        _messages.add(
          _SupportMessage(assistant: true, text: answer['reply'] as String),
        );
        _suggestions = List<String>.from(answer['suggested_questions'] as List);
        _message.clear();
      });
      _scrollToBottom();
    } on BackendException catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.message;
          if (_messages.isNotEmpty &&
              !_messages.last.assistant &&
              _messages.last.text == text) {
            _messages.removeLast();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Bagoo Support could not send that message. Please try again.';
          if (_messages.isNotEmpty &&
              !_messages.last.assistant &&
              _messages.last.text == text) {
            _messages.removeLast();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _talkToPerson() async {
    final id = (widget.user['id'] as num?)?.toInt();
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          repository: widget.repository,
          userId: id,
          receiverId: 2,
          conversationTitle: 'Bagoo Customer Care',
          canAttach: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Help & Support'),
      actions: [
        IconButton(
          tooltip: 'Talk to Bagoo Customer Care',
          onPressed: widget.available ? _talkToPerson : null,
          icon: const Icon(Icons.support_agent_outlined),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              if (!widget.available)
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Icon(
                        Icons.support_agent_outlined,
                        size: 44,
                        color: BagooTheme.crimson,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Support is available after buyer approval',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your account is ${widget.user['status']?.toString().replaceAll('_', ' ') ?? 'not approved yet'}. You can browse the marketplace while your buyer account is reviewed.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: BagooTheme.muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                _assistantHeader(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Notice(_error!, error: true),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _TypingIndicator();
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
                ),
                if (!_sending && _suggestions.isNotEmpty) _suggestionList(),
                _composer(),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _assistantHeader() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: BagooTheme.border)),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          radius: 19,
          backgroundColor: BagooTheme.rose,
          child: Icon(Icons.support_agent_outlined, color: BagooTheme.crimson),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bagoo Support',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Ask about shopping and your orders',
                style: TextStyle(fontSize: 12, color: BagooTheme.muted),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _sending ? null : _talkToPerson,
          child: const Text('Talk to a person'),
        ),
      ],
    ),
  );

  Widget _suggestionList() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final suggestion in _suggestions)
            ActionChip(
              label: Text(suggestion),
              onPressed: _sending ? null : () => _send(suggestion),
            ),
        ],
      ),
    ),
  );

  Widget _composer() => Material(
    color: Colors.white,
    elevation: 4,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _orderNumber,
            enabled: !_sending,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Order number (optional)',
              prefixIcon: Icon(Icons.receipt_long_outlined),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _message,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'How can Bagoo help?',
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send message',
                onPressed: _sending ? null : () => _send(),
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Bagoo Support can explain your account details. It cannot change an order or issue a refund.',
              style: TextStyle(fontSize: 11, color: BagooTheme.muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SupportMessage {
  const _SupportMessage({required this.assistant, required this.text});
  final bool assistant;
  final String text;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _SupportMessage message;

  @override
  Widget build(BuildContext context) => Align(
    alignment: message.assistant ? Alignment.centerLeft : Alignment.centerRight,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: message.assistant ? Colors.white : BagooTheme.rose,
        border: Border.all(
          color: message.assistant ? BagooTheme.border : BagooTheme.rose,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message.text, style: const TextStyle(height: 1.55)),
    ),
  );
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Semantics(
        label: 'Bagoo Support is preparing a reply',
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}
