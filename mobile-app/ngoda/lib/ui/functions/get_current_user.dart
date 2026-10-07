import 'package:ngoda/data_models/auth/decoded_user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

DecodedUser getCurrentUser() {
  final user = Supabase.instance.client.auth.currentUser;

  if (user == null) {
    return const DecodedUser(
      userId: null,
      email: null,
      phoneNumber: null,
      role: null,
      isAuthenticated: false,
    );
  }

  final rawRole = user.appMetadata['role'];

  final role = rawRole?.toString().trim().toLowerCase();

  return DecodedUser(
    userId: user.id,
    email: user.email,
    phoneNumber: user.phone,
    role: role == null || role.isEmpty ? null : role,
    isAuthenticated: true,
  );
}
