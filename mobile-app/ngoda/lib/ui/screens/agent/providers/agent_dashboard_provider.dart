import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/agent/agent_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/agent/services/agent_dashboard_service_provider.dart';

final agentDashboardProvider = FutureProvider<R<AgentDashboard>>((ref) async {
  final service = ref.read(agentDashboardServiceProvider);

  return service.load();
});
