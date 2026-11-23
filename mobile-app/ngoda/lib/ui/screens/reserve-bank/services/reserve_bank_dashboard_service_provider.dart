import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/reserve-bank/services/reserve_bank_api_service_provider.dart';
import 'package:ngoda/ui/screens/reserve-bank/services/reserve_bank_dashboard_service.dart';

final reserveBankDashboardServiceProvider =
    Provider<ReserveBankDashboardService>((ref) {
      final api = ref.read(reserveBankApiServiceProvider);

      return ReserveBankDashboardService(api);
    });
