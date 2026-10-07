import 'package:supabase_flutter/supabase_flutter.dart';

String extractFunctionError(FunctionException error) {
  final details = error.details;

  if (details is Map) {
    final messageKey = details['message_key']?.toString().trim();

    if (messageKey != null && messageKey.isNotEmpty) {
      return messageKey;
    }

    final message = details['message']?.toString().trim();

    if (message != null && message.isNotEmpty) {
      return message;
    }
  }

  final detailsMessage = details?.toString().trim();

  if (detailsMessage != null && detailsMessage.isNotEmpty) {
    return detailsMessage;
  }

  final reasonPhrase = error.reasonPhrase?.trim();

  if (reasonPhrase != null && reasonPhrase.isNotEmpty) {
    return reasonPhrase;
  }

  return 'UNEXPECTED_ERROR';
}
