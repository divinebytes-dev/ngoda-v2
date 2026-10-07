import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/agent/services/agent_api_service_provider.dart';
import 'package:ngoda/ui/screens/agent/services/agent_dashboard_service.dart';

final agentDashboardServiceProvider = Provider<AgentDashboardService>((ref) {
  final api = ref.read(agentApiServiceProvider);

  return AgentDashboardService(api);
});
