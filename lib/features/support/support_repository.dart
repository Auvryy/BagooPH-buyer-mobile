import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';

class SupportAnswer {
  const SupportAnswer({required this.reply, required this.suggestions});

  final String reply;
  final List<String> suggestions;
}

class SupportAssistantRepository {
  SupportAssistantRepository(this.buyer);

  final BuyerRepository buyer;

  Future<SupportAnswer> ask(String message, {String? orderNumber}) async {
    final question = message.trim();
    final order = orderNumber?.trim() ?? '';
    final errors = <String, String>{
      if (question.isEmpty) 'message': 'Enter a question for Bagoo Support.',
      if (question.runes.length > 1000)
        'message': 'Keep your message within 1,000 characters.',
      if (order.runes.length > 50)
        'order_number': 'Keep the order number within 50 characters.',
    };
    if (errors.isNotEmpty) {
      throw BackendException('Check the highlighted fields.', fields: errors);
    }
    final result = await buyer.session.jsonPost('/buyer/support/assistant', {
      'message': question,
      if (order.isNotEmpty) 'order_number': order,
    });
    final reply = result['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const BackendException(
        'Bagoo Support could not confirm a response. Please try again.',
      );
    }
    final suggestions = result['suggested_questions'];
    final cleanSuggestions = <String>[];
    final seenSuggestions = <String>{};
    if (suggestions is List) {
      for (final value in suggestions.take(30)) {
        if (value is! String) continue;
        final question = value.trim();
        if (question.isEmpty ||
            question.runes.length > 1000 ||
            !seenSuggestions.add(question)) {
          continue;
        }
        cleanSuggestions.add(question);
        if (cleanSuggestions.length == 3) break;
      }
    }
    return SupportAnswer(
      reply: reply.trim(),
      suggestions: List.unmodifiable(cleanSuggestions),
    );
  }
}
