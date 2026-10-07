import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/vendor/vendor_dashboard.dart';
import 'package:ngoda/ui/screens/vendor/service/vendor_api_service.dart';

class VendorDashboardService {
  const VendorDashboardService(this.vendorApiService);

  final VendorApiService vendorApiService;

  Future<R<VendorDashboard>> load() async {
    try {
      final response = await vendorApiService.getDashboard();

      final walletData = response['wallet'];

      if (walletData is! Map) {
        throw Exception('Invalid vendor wallet response');
      }

      final wallet = Map<String, dynamic>.from(walletData);

      final agentWallet = wallet['agent'];
      final customerWallet = wallet['customer'];
      final merchantWallet = wallet['merchant'];

      final dailySummary = response['dailySummary'];

      final loanSummary = response['loanSummary'];

      final currencies = response['currencies'];

      if (agentWallet is! Map) {
        throw Exception('Invalid vendor agent wallet response');
      }

      if (customerWallet is! Map) {
        throw Exception('Invalid vendor customer wallet response');
      }

      if (merchantWallet is! Map) {
        throw Exception('Invalid vendor merchant wallet response');
      }

      if (dailySummary is! Map) {
        throw Exception('Invalid vendor daily summary response');
      }

      if (loanSummary is! Map) {
        throw Exception('Invalid vendor loan summary response');
      }

      if (currencies == null) {
        throw Exception('Invalid vendor currencies response');
      }

      final dashboard = VendorDashboard.fromJson(
        agentWalletJson: Map<String, dynamic>.from(agentWallet),
        customerWalletJson: Map<String, dynamic>.from(customerWallet),
        merchantWalletJson: Map<String, dynamic>.from(merchantWallet),
        dailySummaryJson: Map<String, dynamic>.from(dailySummary),
        loanSummaryJson: Map<String, dynamic>.from(loanSummary),
        currencies: currencies,
      );

      return R(result: dashboard);
    } catch (error) {
      return R(error: error.toString());
    }
  }
}
