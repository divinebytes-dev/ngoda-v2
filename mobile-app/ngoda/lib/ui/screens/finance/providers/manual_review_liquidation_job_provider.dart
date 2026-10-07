import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/loan/liquidation/manual_review_liquidation.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final manualReviewLiquidationJobProvider = FutureProvider.autoDispose
    .family<R<ManualReviewLiquidationDetail>, String>((ref, jobId) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.fetchLiquidationManualReviewJob(jobId);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
