import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/functions/identifier_validation.dart';

IdentifierType getIdentifierType(String value) {
  final identifier = value.trim();

  if (isValidEmail(identifier)) {
    return IdentifierType.email;
  }

  if (isValidPhoneNumber(identifier)) {
    return IdentifierType.phone;
  }

  return IdentifierType.userId;
}

bool isValidUserId(String userId) {
  final value = userId.trim();

  if (value.isEmpty) {
    return false;
  }

  final regex = RegExp(
    r'^[0-9a-fA-F]{8}-'
    r'[0-9a-fA-F]{4}-'
    r'[1-5][0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-'
    r'[0-9a-fA-F]{12}$',
  );

  return regex.hasMatch(value);
}

String? validateIdentifier(String value) {
  final identifier = value.trim();

  if (identifier.isEmpty) {
    return 'Email, phone number or user ID is required';
  }

  if (identifier.contains('@')) {
    if (!isValidEmail(identifier)) {
      return 'Invalid email address';
    }

    return null;
  }

  if (identifier.startsWith('+') || RegExp(r'^\d+$').hasMatch(identifier)) {
    if (!isValidPhoneNumber(identifier)) {
      return 'Invalid phone number';
    }

    return null;
  }

  if (!isValidUserId(identifier)) {
    return 'Invalid user ID';
  }

  return null;
}
