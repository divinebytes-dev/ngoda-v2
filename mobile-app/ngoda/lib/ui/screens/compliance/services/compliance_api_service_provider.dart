import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/compliance/services/compliance_api_service.dart';

final complianceApiServiceProvider = Provider<ComplianceApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);
  return ComplianceApiService(functions);
});
