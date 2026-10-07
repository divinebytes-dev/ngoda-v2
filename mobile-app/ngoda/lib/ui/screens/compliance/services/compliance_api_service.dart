import 'package:ngoda/data_models/kyc/user_kyc_review_page.dart';
import 'package:ngoda/data_models/params/kyc_review_params.dart';
import 'package:ngoda/data_models/user/user_details.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ComplianceApiService {
  ComplianceApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<Map<String, dynamic>> getDashboard() async {
    return _functions.invokeData(
      functionName: 'compliance-dashboard',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid compliance dashboard response',
    );
  }

  Future<UserDetails> fetchUserKycReviewDetails(String userId) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-user-kyc-review-details',
      method: HttpMethod.get,
      queryParameters: {'user_id': userId},
      invalidResponseMessage: 'Invalid user KYC review details response',
    );

    return UserDetails.fromJson(data);
  }

  Future<UserDetails> updateUserKyc({
    required String userId,
    required String decision,
    String? comment,
  }) async {
    final data = await _functions.invokeData(
      functionName: 'upsert-user-kyc',
      body: {'userId': userId, 'decision': decision, 'comment': comment},
      invalidResponseMessage: 'Invalid KYC review response',
    );

    return UserDetails.fromJson(data);
  }

  Future<UserKycReviewPage> fetchPendingUserKycReviews(
    KycReviewQueueParams params,
  ) async {
    final data = await _functions.invokeData(
      functionName: 'fetch-pending-user-kyc',
      method: HttpMethod.get,
      queryParameters: params.toQueryParameters(),
      invalidResponseMessage: 'Invalid pending KYC reviews response',
    );

    return UserKycReviewPage.fromJson(data);
  }
}
