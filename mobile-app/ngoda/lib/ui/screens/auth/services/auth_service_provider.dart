import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/auth/services/auth_api_service.dart';
import 'package:ngoda/ui/screens/auth/services/auth_service.dart';

final authApiServiceProvider = Provider<AuthApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return AuthApiService(functions);
});

final authServiceProvider = Provider<AuthService>((ref) {
  final apiService = ref.read(authApiServiceProvider);

  return AuthService(apiService: apiService);
});
