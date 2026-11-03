class ChatHistoryUpdate {
  const ChatHistoryUpdate({
    required this.messages,
    required this.hasNewMessages,
  });

  final List<Map<String, dynamic>> messages;
  final bool hasNewMessages;
}

ChatHistoryUpdate reconcileChatHistory(
  List<Map<String, dynamic>> current,
  List<Map<String, dynamic>> received,
) {
  final seen = <Object?>{};
  var currentIndex = 0;
  var unchanged = true;

  for (final message in received) {
    if (!seen.add(message['id'])) continue;
    if (currentIndex >= current.length ||
        !_sameDisplayedMessage(current[currentIndex], message)) {
      unchanged = false;
    }
    currentIndex++;
  }

  if (currentIndex != current.length) unchanged = false;
  if (unchanged) {
    return ChatHistoryUpdate(messages: current, hasNewMessages: false);
  }

  final ids = <Object?>{};
  final messages = <Map<String, dynamic>>[];
  for (final message in received) {
    if (ids.add(message['id'])) messages.add(message);
  }

  final currentIds = {for (final message in current) message['id']};
  return ChatHistoryUpdate(
    messages: messages,
    hasNewMessages: messages.any(
      (message) => !currentIds.contains(message['id']),
    ),
  );
}

bool _sameDisplayedMessage(
  Map<String, dynamic> current,
  Map<String, dynamic> received,
) {
  for (final key in const [
    'id',
    'sender_id',
    'receiver_id',
    'message',
    'created_at',
    'attachment_url',
  ]) {
    if (current[key] != received[key]) return false;
  }

  final currentProduct = current['product'];
  final receivedProduct = received['product'];
  if (currentProduct == null || receivedProduct == null) {
    return currentProduct == receivedProduct;
  }
  if (currentProduct is! Map || receivedProduct is! Map) {
    return currentProduct == receivedProduct;
  }

  for (final key in const ['slug', 'featured_image', 'name', 'price']) {
    if (currentProduct[key] != receivedProduct[key]) return false;
  }
  return true;
}
