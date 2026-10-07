bool isValidEmail(String value) {
  final email = value.trim();

  if (email.isEmpty) {
    return false;
  }

  final emailRegex = RegExp(
    r'^[A-Za-z0-9.!#$%&'
    r"'*+/=?^_`{|}~-]+"
    r'@[A-Za-z0-9]'
    r'(?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9]'
    r'(?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
  );

  return emailRegex.hasMatch(email);
}

bool isValidPhoneNumber(String value) {
  final phoneNumber = value.trim().replaceAll(' ', '');

  if (phoneNumber.isEmpty) {
    return false;
  }

  final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');

  return phoneRegex.hasMatch(phoneNumber);
}
