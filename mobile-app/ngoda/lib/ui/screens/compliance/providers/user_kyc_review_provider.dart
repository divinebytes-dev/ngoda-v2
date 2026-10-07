import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/user/user_details.dart';
import 'package:ngoda/ui/screens/compliance/services/compliance_api_service_provider.dart';

final userKycReviewProvider = FutureProvider.family
    .autoDispose<R<UserDetails>, String>((ref, userId) async {
      try {
        final api = ref.read(complianceApiServiceProvider);
        final response = await api.fetchUserKycReviewDetails(userId);
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
