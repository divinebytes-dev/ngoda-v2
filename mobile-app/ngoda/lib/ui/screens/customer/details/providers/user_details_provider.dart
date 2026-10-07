import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/user/user_details.dart';

import 'package:ngoda/ui/screens/customer/details/services/user_details_api_service_provider.dart';

final userDetailsProvider = FutureProvider.autoDispose<R<UserDetails>>((
  ref,
) async {
  try {
    final service = ref.read(userDetailsApiServiceProvider);

    final userDetails = await service.fetchUserDetails();

    return R<UserDetails>(result: userDetails);
  } catch (error) {
    return R<UserDetails>(error: error.toString());
  }
});
