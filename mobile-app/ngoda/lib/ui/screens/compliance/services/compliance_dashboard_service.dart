import 'package:logging/logging.dart';
import 'package:ngoda/data_models/compliance/compliance_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';

import 'package:ngoda/ui/screens/compliance/services/compliance_api_service.dart';

class ComplianceDashboardService {
  final ComplianceApiService complianceApiService;

  ComplianceDashboardService(this.complianceApiService);

  final logger = Logger("ComplianceDashboardService");
  Future<R<ComplianceDashboard>> load() async {
    try {
      final response = await complianceApiService.getDashboard();

      final dashboard = ComplianceDashboard.fromJson(
        Map<String, dynamic>.from(response),
      );

      return R(result: dashboard);
    } catch (e) {
      logger.info("admin dashboard error : ${e.toString()}");
      return R(error: e.toString());
    }
  }
}
