import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/reserve-bank/reserve_bank_dashboard.dart';
import 'package:ngoda/ui/screens/reserve-bank/services/reserve_bank_api_service.dart';

class ReserveBankDashboardService {
  const ReserveBankDashboardService(this._apiService);

  final ReserveBankApiService _apiService;

  Future<R<ReserveBankDashboard>> load() async {
    try {
      final response = await _apiService.getDashboard();
      final dashboard = ReserveBankDashboard.fromJson(response);

      return R(result: dashboard);
    } catch (error) {
      return R(error: error.toString());
    }
  }
}
