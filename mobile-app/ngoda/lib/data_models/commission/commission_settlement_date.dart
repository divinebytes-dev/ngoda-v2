class CommissionSettlementDate {
  const CommissionSettlementDate({
    required this.currencyCode,
    this.startDate,
    this.endDate,
    this.nextStartDate,
    this.documentNumber,
    this.status,
    this.paymentUnderway,
  });

  final String currencyCode;

  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? nextStartDate;

  final String? documentNumber;
  final String? status;
  final bool? paymentUnderway;

  factory CommissionSettlementDate.fromJson(Map<String, dynamic> json) {
    return CommissionSettlementDate(
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      startDate: _toDateTime(json['start_date']),
      endDate: _toDateTime(json['end_date']),
      nextStartDate: json['end_date'] != null
          ? _toDateTime(json['next_start_date'])
          : null,
      documentNumber: _toNullableString(json['document_number']),
      status: _toNullableNormalizedString(json['status']),
      paymentUnderway: json['payment_underway'] is bool
          ? json['payment_underway'] as bool
          : null,
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim();

    if (normalized.isEmpty) {
      return null;
    }

    return DateTime.tryParse(normalized);
  }

  static String? _toNullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim();

    return normalized.isEmpty ? null : normalized;
  }

  static String? _toNullableNormalizedString(dynamic value) {
    return _toNullableString(value)?.toLowerCase();
  }
}
