import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/admin/service/admin_api_service.dart';

final adminApiServiceProvider = Provider<AdminApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return AdminApiService(functions);
});
