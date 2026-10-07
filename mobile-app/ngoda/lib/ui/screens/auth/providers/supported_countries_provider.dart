import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/country/supported_country.dart';
import 'package:ngoda/ui/screens/auth/services/auth_service_provider.dart';

final supportedCountriesProvider = FutureProvider<R<List<SupportedCountry>>>((
  ref,
) async {
  try {
    final apiService = ref.read(authApiServiceProvider);

    final response = await apiService.getCountries();

    return R(result: response);
  } catch (error) {
    return R(error: error.toString());
  }
});
