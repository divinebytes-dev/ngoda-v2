class SupportedCountry {
  const SupportedCountry({required this.code, required this.name});

  final String code;
  final String name;

  factory SupportedCountry.fromJson(Map<String, dynamic> json) {
    return SupportedCountry(
      code: json['country_code']?.toString().trim().toLowerCase() ?? '',
      name: json['name']?.toString().trim() ?? '',
    );
  }
}
