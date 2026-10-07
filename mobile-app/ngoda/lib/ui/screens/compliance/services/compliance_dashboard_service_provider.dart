import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/ui/screens/compliance/services/compliance_api_service_provider.dart';
import 'package:ngoda/ui/screens/compliance/services/compliance_dashboard_service.dart';

final complianceDashboardServiceProvider = Provider<ComplianceDashboardService>(
  (ref) {
    final api = ref.read(complianceApiServiceProvider);

    return ComplianceDashboardService(api);
  },
);
