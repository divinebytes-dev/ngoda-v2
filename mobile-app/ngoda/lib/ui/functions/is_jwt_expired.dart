bool isJwtExpired(Object? error) {
  if (error == null) {
    return false;
  }

  final message = error.toString().trim().toLowerCase();

  if (message.isEmpty) {
    return false;
  }

  return message.contains('jwt') && message.contains('expired');
}
