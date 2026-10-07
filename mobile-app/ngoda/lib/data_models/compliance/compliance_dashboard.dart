import 'package:ngoda/data_models/kyc/kyc_country_summary.dart';
import 'package:ngoda/data_models/kyc/kyc_summary.dart';

class ComplianceDashboard {
  ComplianceDashboard({
    required this.summary,
    required List<KycCountrySummary> countries,
  }) : countries = List.unmodifiable(countries);

  final KycSummary summary;

  final List<KycCountrySummary> countries;

  factory ComplianceDashboard.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    return ComplianceDashboard(
      summary: KycSummary.fromJson(_asMap(data['summary'])),
      countries: _parseCountries(data['countries']),
    );
  }

  int get countryCount => countries.length;

  bool get hasPendingReviews => summary.hasPendingReviews;

  List<KycCountrySummary> get sortedCountries {
    final result = [...countries]
      ..sort((first, second) => second.totalUsers.compareTo(first.totalUsers));

    return List.unmodifiable(result);
  }

  KycCountrySummary? country(String countryCode) {
    final normalized = countryCode.trim().toLowerCase();

    for (final country in countries) {
      if (country.countryCode == normalized) {
        return country;
      }
    }

    return null;
  }

  static List<KycCountrySummary> _parseCountries(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (country) =>
              KycCountrySummary.fromJson(Map<String, dynamic>.from(country)),
        )
        .toList();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
