import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/services/supabase_function_service.dart';

final supabaseFunctionServiceProvider = Provider<SupabaseFunctionService>((
  ref,
) {
  return SupabaseFunctionService();
});
