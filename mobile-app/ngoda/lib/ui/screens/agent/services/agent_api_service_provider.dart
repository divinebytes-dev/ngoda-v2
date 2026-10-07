import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/agent/services/agent_api_service.dart';

final agentApiServiceProvider = Provider<AgentApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return AgentApiService(functions);
});
