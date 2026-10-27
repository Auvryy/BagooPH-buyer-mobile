import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';

class SupportAssistantRepository {
  SupportAssistantRepository(this.buyer);

  final BuyerRepository buyer;

  Future<Map<String, dynamic>> ask(
    String message, {
    String? orderNumber,
  }) async {
    final result = await buyer.session.jsonPost('/buyer/support/assistant', {
      'message': message,
      if (orderNumber != null && orderNumber.trim().isNotEmpty)
        'order_number': orderNumber.trim(),
    });
    final reply = result['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const BackendException(
        'Bagoo Support could not confirm a response. Please try again.',
      );
    }
    return {
      'reply': reply.trim(),
      'suggested_questions':
          (result['suggested_questions'] is List
                  ? result['suggested_questions'] as List
                  : const <dynamic>[])
              .whereType<String>()
              .map((question) => question.trim())
              .where((question) => question.isNotEmpty)
              .take(3)
              .toList(),
    };
  }
}
