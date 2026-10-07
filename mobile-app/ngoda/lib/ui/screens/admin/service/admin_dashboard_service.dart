import 'package:logging/logging.dart';
import 'package:ngoda/data_models/admin/admin_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/admin/service/admin_api_service.dart';

class AdminDashboardService {
  AdminDashboardService(this._adminApiService);

  final AdminApiService _adminApiService;

  final Logger _logger = Logger('AdminDashboardService');

  Future<R<AdminDashboard>> load() async {
    try {
      final data = await _adminApiService.getDashboard();

      final dashboard = AdminDashboard.fromJson(data);

      return R(result: dashboard);
    } catch (e) {
      _logger.warning('Admin dashboard error: $e');

      return R(error: e.toString());
    }
  }
}
