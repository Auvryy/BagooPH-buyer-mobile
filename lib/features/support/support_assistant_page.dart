import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
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
  static const _greeting = _SupportMessage(
    assistant: true,
    text: 'Hi! Ask me about Bagoo shopping, checkout, orders, payments, delivery, or returns.',
  );
  static const _initialSuggestions = [
    'Where is my latest order?',
    'How do I request a return?',
    'Why can’t I check out?',
  ];

  final _message = TextEditingController();
  final _orderNumber = TextEditingController();
  final _messageFocus = FocusNode();
  final _orderFocus = FocusNode();
  final _scroll = ScrollController();
  final _messages = <_SupportMessage>[_greeting];
  late SupportAssistantRepository _support;
  List<String> _suggestions = _initialSuggestions;
  Map<String, String> _fieldErrors = {};
  String? _error;
  int _generation = 0;
  bool _sending = false;
  bool _openingChat = false;
  bool _orderExpanded = false;
  bool _sessionExpired = false;
  bool _accessDenied = false;

  int? get _userId {
    final id = widget.user['id'];
    return id is num && id > 0 ? id.toInt() : null;
  }

  bool get _available =>
      widget.available && _userId != null && !_sessionExpired && !_accessDenied;

  @override
  void initState() {
    super.initState();
    _support = SupportAssistantRepository(widget.repository);
  }

  @override
  void didUpdateWidget(covariant SupportAssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user['id'] != widget.user['id'] ||
        !identical(oldWidget.repository, widget.repository) ||
        oldWidget.available != widget.available) {
      _generation++;
      _support = SupportAssistantRepository(widget.repository);
      _messages
        ..clear()
        ..add(_greeting);
      _suggestions = _initialSuggestions;
      _message.clear();
      _orderNumber.clear();
      _fieldErrors = {};
      _error = null;
      _sending = false;
      _openingChat = false;
      _orderExpanded = false;
      _sessionExpired = false;
      _accessDenied = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _message.dispose();
    _orderNumber.dispose();
    _messageFocus.dispose();
    _orderFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final bottom = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(bottom);
      } else {
        _scroll.animateTo(
          bottom,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _useSuggestion(String question) {
    if (_sending || !_available || _message.text.trim().isNotEmpty) return;
    _message.value = TextEditingValue(
      text: question,
      selection: TextSelection.collapsed(offset: question.length),
    );
    _messageFocus.requestFocus();
    _scrollToBottom();
  }

  Future<void> _send() async {
    if (_sending || !_available) return;
    final text = _message.text.trim();
    if (text.isEmpty) return;
    final generation = ++_generation;
    final submitted = _SupportMessage(assistant: false, text: text);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _sending = true;
      _error = null;
      _fieldErrors = {};
      _messages.add(submitted);
    });
    _scrollToBottom();
    try {
      final answer = await _support.ask(text, orderNumber: _orderNumber.text);
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages.add(_SupportMessage(assistant: true, text: answer.reply));
        _suggestions = answer.suggestions;
        _message.clear();
      });
      _scrollToBottom();
    } on BackendException catch (exception) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages.remove(submitted);
        if (exception.status == 401 ||
            exception.status == 419 ||
            exception.status == 403) {
          _sessionExpired = exception.status != 403;
          _accessDenied = exception.status == 403;
          _messages.clear();
          _suggestions = const [];
          _message.clear();
          _orderNumber.clear();
        } else {
          _fieldErrors = Map.of(exception.fields);
          _error = exception.fields.isEmpty
              ? exception.message
              : exception.fields.values.toSet().join('\n');
          if (_fieldErrors.containsKey('order_number')) _orderExpanded = true;
        }
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages.remove(submitted);
        _error = 'Bagoo Support could not send that message. Please try again.';
      });
      _scrollToBottom();
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _talkToPerson() async {
    final id = _userId;
    if (!_available || _openingChat || id == null) return;
    final generation = _generation;
    setState(() => _openingChat = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            repository: widget.repository,
            userId: id,
            receiverId: 2,
            conversationTitle: 'Bagoo Customer Care',
          ),
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _openingChat = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Help & Support',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: 'Chat with Bagoo Customer Care',
          onPressed: _available && !_openingChat ? _talkToPerson : null,
          icon: const Icon(Icons.support_agent_outlined),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: !_available
              ? _unavailable()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxHeight < 420 ||
                        MediaQuery.textScalerOf(context).scale(16) > 24;
                    if (compact) return _conversation(includeComposer: true);
                    return Column(
                      children: [
                        Expanded(child: _conversation()),
                        _composer(),
                      ],
                    );
                  },
                ),
        ),
      ),
    ),
  );

  Widget _unavailable() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const ExcludeSemantics(
        child: Icon(
          Icons.support_agent_outlined,
          size: 44,
          color: BagooTheme.crimson,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        _sessionExpired ? 'Sign in to continue' : 'Check your account access',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        _sessionExpired
            ? 'Your session expired. Sign in again to use Bagoo Support.'
            : 'Support chat requires an eligible buyer account. Check your identity verification and account status in Profile.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: BagooTheme.muted, height: 1.6),
      ),
      const SizedBox(height: 16),
      if (_sessionExpired)
        FilledButton(
          onPressed: () => BuyerActions.login(context, destination: 'profile'),
          child: const Text('Sign in'),
        ),
      OutlinedButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Back to Profile'),
      ),
    ],
  );

  Widget _conversation({bool includeComposer = false}) => ListView.builder(
    controller: _scroll,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.all(16),
    itemCount: _messages.length + 4 + (includeComposer ? 1 : 0),
    itemBuilder: (context, index) {
      if (index == 0) return _assistantHeader();
      if (index <= _messages.length) {
        return _MessageBubble(message: _messages[index - 1]);
      }
      final footer = index - _messages.length;
      if (footer == 1) {
        return _sending ? const _TypingIndicator() : const SizedBox.shrink();
      }
      if (footer == 2) return _suggestionList();
      if (footer == 3) return _errorPanel();
      return _composer();
    },
  );

  Widget _assistantHeader() => const Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        ExcludeSemantics(
          child: CircleAvatar(
            radius: 19,
            backgroundColor: BagooTheme.rose,
            child: Icon(
              Icons.support_agent_outlined,
              color: BagooTheme.crimson,
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bagoo Support',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Guidance about shopping and your orders',
                style: TextStyle(fontSize: 13, color: BagooTheme.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _suggestionList() => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _message,
    builder: (context, draft, _) {
      if (_sending || _suggestions.isEmpty || draft.text.trim().isNotEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a question, then edit or send it.',
              style: TextStyle(fontSize: 12, color: BagooTheme.muted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in _suggestions)
                  OutlinedButton(
                    onPressed: () => _useSuggestion(suggestion),
                    child: Text(suggestion),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _errorPanel() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Notice(_error!, error: true),
            if (_fieldErrors.isEmpty)
              OutlinedButton.icon(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }

  void _clearFieldError(String key) {
    if (_fieldErrors.containsKey(key)) {
      setState(() => _fieldErrors.remove(key));
    }
  }

  Widget _composer() => Material(
    key: const ValueKey('support-composer'),
    color: Colors.white,
    shape: const Border(top: BorderSide(color: BagooTheme.line)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _sending
                  ? null
                  : () => setState(() {
                      _orderExpanded = !_orderExpanded;
                    }),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(
                _orderExpanded ? 'Hide order number' : 'Add an order number',
              ),
            ),
          ),
          if (_orderExpanded) ...[
            TextField(
              controller: _orderNumber,
              focusNode: _orderFocus,
              enabled: !_sending,
              maxLength: 50,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _messageFocus.requestFocus(),
              onChanged: (_) => _clearFieldError('order_number'),
              decoration: InputDecoration(
                labelText: 'Order number (optional)',
                counterText: '',
                errorText: _fieldErrors['order_number'],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _message,
                  focusNode: _messageFocus,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => _clearFieldError('message'),
                  decoration: InputDecoration(
                    labelText: 'Message',
                    hintText: 'How can Bagoo help?',
                    counterText: '',
                    errorText: _fieldErrors['message'],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _message,
                builder: (context, value, _) => IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending || value.text.trim().isEmpty
                      ? null
                      : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Replies provide guidance. They do not change orders or issue refunds.',
            style: TextStyle(fontSize: 12, color: BagooTheme.muted),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.assistant ? 'Bagoo Support' : 'You',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          SelectableText(message.text, style: const TextStyle(height: 1.55)),
        ],
      ),
    ),
  );
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Semantics(
      label: 'Bagoo Support is preparing a reply',
      liveRegion: true,
      child: const ExcludeSemantics(
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    ),
  );
}
