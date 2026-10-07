import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/kyc/user_kyc_review_page.dart';
import 'package:ngoda/data_models/params/kyc_review_params.dart';
import 'package:ngoda/ui/screens/compliance/services/compliance_api_service_provider.dart';

final complianceKycReviewsProvider = FutureProvider.family
    .autoDispose<R<UserKycReviewPage>, KycReviewQueueParams>((
      ref,
      params,
    ) async {
      try {
        final api = ref.read(complianceApiServiceProvider);
        final response = await api.fetchPendingUserKycReviews(params);
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
