class UserKycDetails {
  const UserKycDetails({
    required this.idType,
    required this.idNumber,
    required this.expiryDate,
    required this.occupation,
    required this.sourceOfFunds,
    required this.taxNumber,
    required this.status,
  });

  final String? idType;

  final String? idNumber;

  final DateTime? expiryDate;

  final String? occupation;

  final String? sourceOfFunds;

  final String? taxNumber;

  /// Dynamic backend KYC status.
  final String? status;

  factory UserKycDetails.fromJson(Map<String, dynamic> json) {
    return UserKycDetails(
      idType: _optionalString(json['id_type'])?.toLowerCase(),
      idNumber: _optionalString(json['id_number']),
      expiryDate: _optionalDate(json['expiry_date']),
      occupation: _optionalString(json['occupation']),
      sourceOfFunds: _optionalString(json['source_of_funds']),
      taxNumber: _optionalString(json['tax_number']),
      status: _optionalString(
        json['kyc_status'] ?? json['status'],
      )?.toLowerCase(),
    );
  }

  UserKycDetails copyWith({
    String? idType,
    bool clearIdType = false,
    String? idNumber,
    bool clearIdNumber = false,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    String? occupation,
    bool clearOccupation = false,
    String? sourceOfFunds,
    bool clearSourceOfFunds = false,
    String? taxNumber,
    bool clearTaxNumber = false,
    String? status,
    bool clearStatus = false,
  }) {
    return UserKycDetails(
      idType: clearIdType ? null : idType?.trim().toLowerCase() ?? this.idType,
      idNumber: clearIdNumber ? null : idNumber ?? this.idNumber,
      expiryDate: clearExpiryDate ? null : expiryDate ?? this.expiryDate,
      occupation: clearOccupation ? null : occupation ?? this.occupation,
      sourceOfFunds: clearSourceOfFunds
          ? null
          : sourceOfFunds ?? this.sourceOfFunds,
      taxNumber: clearTaxNumber ? null : taxNumber ?? this.taxNumber,
      status: clearStatus ? null : status?.trim().toLowerCase() ?? this.status,
    );
  }

  bool get hasIdentification => idType != null && idNumber != null;

  bool get hasExpiryDate => expiryDate != null;

  Map<String, dynamic> toQuery() {
    return {
      'idType': idType?.trim().toLowerCase(),
      'idNumber': idNumber,
      'expiryDate': expiryDate?.toIso8601String(),
      'occupation': occupation,
      'sourceOfFunds': sourceOfFunds,
      'taxNumber': taxNumber,
      'status': status,
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

DateTime? _optionalDate(dynamic value) {
  final raw = _optionalString(value);

  if (raw == null) {
    return null;
  }

  return DateTime.tryParse(raw);
}
