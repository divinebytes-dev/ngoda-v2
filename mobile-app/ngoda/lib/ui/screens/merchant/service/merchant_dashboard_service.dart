import 'package:ngoda/data_models/merchant/merchant_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/merchant/service/merchant_api_service.dart';

class MerchantDashboardService {
  const MerchantDashboardService(this._merchantApiService);

  final MerchantApiService _merchantApiService;

  Future<R<MerchantDashboard>> load() async {
    try {
      final response = await _merchantApiService.getDashboard();

      final dashboard = MerchantDashboard.fromJson(
        agentWalletJson: Map<String, dynamic>.from(
          response['wallet']['agent'] as Map,
        ),
        merchantWalletJson: Map<String, dynamic>.from(
          response['wallet']['merchant'] as Map,
        ),
        dailySummaryJson: Map<String, dynamic>.from(
          response['dailySummary'] as Map,
        ),
        currencies: response['currencies'],
        isCreditAgent: response['isCreditAgent'] as bool? ?? false,
        creditAgentJson:
            response['creditAgent'] as Map<String, dynamic>? ?? const {},
      );

      return R(result: dashboard);
    } catch (error) {
      return R(error: error.toString());
    }
  }
}
