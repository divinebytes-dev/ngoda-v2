class UserContactDetails {
  const UserContactDetails({
    required this.email,
    required this.phone,
    required this.countryCode,
    required this.countryName,
    required this.residentialAddress,
    required this.city,
    required this.provinceState,
  });

  final String? email;

  final String? phone;

  final String? countryCode;

  final String? countryName;

  final String? residentialAddress;

  final String? city;

  final String? provinceState;

  factory UserContactDetails.fromJson(Map<String, dynamic> json) {
    return UserContactDetails(
      email: _optionalString(json['email']),
      phone: _optionalString(json['phone']),
      countryCode: _optionalString(json['country_code'])?.toLowerCase(),
      countryName: _optionalString(json['country_name']),
      residentialAddress: _optionalString(json['residential_address']),
      city: _optionalString(json['city']),
      provinceState: _optionalString(json['province_state']),
    );
  }

  UserContactDetails copyWith({
    String? email,
    bool clearEmail = false,
    String? phone,
    bool clearPhone = false,
    String? countryCode,
    bool clearCountryCode = false,
    String? countryName,
    bool clearCountryName = false,
    String? residentialAddress,
    bool clearResidentialAddress = false,
    String? city,
    bool clearCity = false,
    String? provinceState,
    bool clearProvinceState = false,
  }) {
    return UserContactDetails(
      email: clearEmail ? null : email ?? this.email,
      phone: clearPhone ? null : phone ?? this.phone,
      countryCode: clearCountryCode
          ? null
          : countryCode?.trim().toLowerCase() ?? this.countryCode,
      countryName: clearCountryName ? null : countryName ?? this.countryName,
      residentialAddress: clearResidentialAddress
          ? null
          : residentialAddress ?? this.residentialAddress,
      city: clearCity ? null : city ?? this.city,
      provinceState: clearProvinceState
          ? null
          : provinceState ?? this.provinceState,
    );
  }

  String? get preferredContact {
    return phone ?? email;
  }

  bool get hasContact => phone != null || email != null;

  String get fullAddress {
    return <String>[
      ?residentialAddress,
      ?city,
      ?provinceState,
      ?countryName,
    ].join(', ');
  }

  bool get hasAddress => fullAddress.isNotEmpty;

  Map<String, dynamic> toQuery() {
    return {
      'email': email,
      'phone': phone,
      'countryCode': countryCode?.trim().toLowerCase(),
      'countryName': countryName,
      'residentialAddress': residentialAddress,
      'city': city,
      'provinceState': provinceState,
    };
  }
}

String? _optionalString(dynamic value) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    return null;
  }

  return result;
}
