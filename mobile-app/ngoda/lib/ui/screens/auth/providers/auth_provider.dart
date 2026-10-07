import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/auth/notifier/auth_notifier.dart';
import 'package:ngoda/ui/screens/auth/state/user_auth_state.dart';

final authProvider = NotifierProvider<AuthNotifier, UserAuthState>(
  AuthNotifier.new,
);
