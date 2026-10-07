import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/treasury/treasury_dashboard.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_api_service.dart';

class TreasuryDashboardService {
  TreasuryDashboardService(this._treasuryApiService);

  final TreasuryApiService _treasuryApiService;

  Future<R<TreasuryDashboard>> load() async {
    try {
      final summary = await _treasuryApiService.getSummary();

      return R(result: summary);
    } catch (error) {
      return R(error: error.toString());
    }
  }
}
