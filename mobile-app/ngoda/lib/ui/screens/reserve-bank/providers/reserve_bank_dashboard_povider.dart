import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/reserve-bank/reserve_bank_dashboard.dart';
import 'package:ngoda/ui/screens/reserve-bank/services/reserve_bank_dashboard_service_provider.dart';

final reserveBankDashboardProvider = FutureProvider<R<ReserveBankDashboard>>((
  ref,
) async {
  final service = ref.read(reserveBankDashboardServiceProvider);

  return service.load();
});
