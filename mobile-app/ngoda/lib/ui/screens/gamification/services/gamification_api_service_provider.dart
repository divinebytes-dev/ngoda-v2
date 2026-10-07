import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/gamification/services/gamification_api_service.dart';

final gamificationApiServiceProvider = Provider<GamificationApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return GamificationApiService(functions);
});
