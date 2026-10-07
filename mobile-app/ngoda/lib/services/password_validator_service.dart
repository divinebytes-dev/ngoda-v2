class PasswordValidatorService {
  PasswordValidatorService._();

  static const int minimumLength = 8;

  static const String requirements =
      'Password must contain at least 8 characters, '
      'including uppercase, lowercase, a number '
      'and a special character.';

  static final RegExp _uppercase = RegExp(r'[A-Z]');

  static final RegExp _lowercase = RegExp(r'[a-z]');

  static final RegExp _number = RegExp(r'[0-9]');

  static final RegExp _specialCharacter = RegExp(
    r'[!@#$%^&*(),.?":{}|<>_\-+=]',
  );

  static bool isValid(String password) {
    return validate(password) == null;
  }

  static String? validate(String password) {
    if (password.isEmpty) {
      return 'Password is required';
    }

    if (password.length < minimumLength) {
      return 'Password must be at least '
          '$minimumLength characters';
    }

    if (!_uppercase.hasMatch(password)) {
      return 'Password must contain an uppercase letter';
    }

    if (!_lowercase.hasMatch(password)) {
      return 'Password must contain a lowercase letter';
    }

    if (!_number.hasMatch(password)) {
      return 'Password must contain a number';
    }

    if (!_specialCharacter.hasMatch(password)) {
      return 'Password must contain a special character';
    }

    return null;
  }
}
