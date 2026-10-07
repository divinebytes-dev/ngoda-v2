import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/compliance/compliance_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/compliance/services/compliance_dashboard_service_provider.dart';

final complianceDashboardProvider = FutureProvider<R<ComplianceDashboard>>((
  ref,
) async {
  final service = ref.read(complianceDashboardServiceProvider);
  return service.load();
});
