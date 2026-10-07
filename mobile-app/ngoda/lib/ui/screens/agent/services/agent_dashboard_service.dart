import 'package:ngoda/data_models/agent/agent_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/agent/services/agent_api_service.dart';

class AgentDashboardService {
  const AgentDashboardService(this._agentApiService);

  final AgentApiService _agentApiService;

  Future<R<AgentDashboard>> load() async {
    try {
      final response = await _agentApiService.getDashboard();

      final dashboard = AgentDashboard.fromJson(
        agentWalletJson: Map<String, dynamic>.from(
          response['wallet']['agent'] as Map,
        ),
        customerWalletJson: Map<String, dynamic>.from(
          response['wallet']['customer'] as Map,
        ),
        dailySummaryJson: response['dailySummary'],
        loanSummaryJson: Map<String, dynamic>.from(
          response['loanSummary'] as Map,
        ),
        currencyList: response['currencies'],
      );

      return R(result: dashboard);
    } catch (error) {
      return R(error: error.toString());
    }
  }
}
