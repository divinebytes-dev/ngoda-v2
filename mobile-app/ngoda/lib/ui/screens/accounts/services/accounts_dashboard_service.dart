import 'package:ngoda/data_models/accounts/accounts_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_api_service.dart';

class AccountsDashboardService {
  final AccountsApiService accountsApiService;

  AccountsDashboardService(this.accountsApiService);

  Future<R<AccountsDashboard>> load() async {
    try {
      final summary = await accountsApiService.getAccountsSummary();

      return R(result: summary);
    } catch (e) {
      return R(error: e.toString());
    }
  }
}
