import 'package:bagoo_buyer_mobile/features/products/chat_history.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> message(int id, String text, {String? productName}) => {
  'id': id,
  'sender_id': 3,
  'receiver_id': 7,
  'message': text,
  'created_at': '2026-11-03T00:00:00Z',
  'attachment_url': null,
  if (productName != null)
    'product': {
      'slug': 'bagoo-item',
      'featured_image': '/images/item.jpg',
      'name': productName,
      'price': 125.0,
    },
};

void main() {
  test('reuses the current list when displayed history is unchanged', () {
    final current = [message(1, 'Hello', productName: 'Item')];
    final received = [message(1, 'Hello', productName: 'Item')];

    final update = reconcileChatHistory(current, received);

    expect(identical(update.messages, current), isTrue);
    expect(update.hasNewMessages, isFalse);
  });

  test('updates changed content for an existing message ID', () {
    final current = [message(1, 'Old text')];

    final update = reconcileChatHistory(current, [message(1, 'Edited text')]);

    expect(update.messages.single['message'], 'Edited text');
    expect(update.hasNewMessages, isFalse);
  });

  test('deduplicates newly received messages and preserves server order', () {
    final current = [message(1, 'First')];

    final update = reconcileChatHistory(current, [
      message(1, 'First'),
      message(2, 'Second'),
      message(2, 'Second duplicate'),
    ]);

    expect(update.messages.map((row) => row['id']), [1, 2]);
    expect(update.hasNewMessages, isTrue);
  });

  test('accepts a shorter authoritative response without scrolling', () {
    final current = [message(1, 'First'), message(2, 'Second')];

    final update = reconcileChatHistory(current, [message(2, 'Second')]);

    expect(update.messages.map((row) => row['id']), [2]);
    expect(update.hasNewMessages, isFalse);
  });
}
