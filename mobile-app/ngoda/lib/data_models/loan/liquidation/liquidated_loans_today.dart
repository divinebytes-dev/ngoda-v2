import 'package:ngoda/services/number_conversion_service.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';

class LiquidatedLoanRow {
  const LiquidatedLoanRow({
    required this.loanId,
    required this.userId,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.surname,
    required this.documentNumber,
    required this.currencyCode,
    required this.principalLiquidated,
    required this.interestLiquidated,
    required this.totalLiquidated,
    required this.loanStatus,
    required this.liquidatedAt,
  });

  final String loanId;
  final String userId;

  final String? email;
  final String? phone;
  final String? firstName;
  final String? surname;

  final String documentNumber;
  final String currencyCode;

  final double principalLiquidated;
  final double interestLiquidated;
  final double totalLiquidated;

  /// Dynamic backend status.
  final String loanStatus;

  final DateTime? liquidatedAt;

  factory LiquidatedLoanRow.fromJson(Map<String, dynamic> json) {
    return LiquidatedLoanRow(
      loanId: json['loan_id']?.toString().trim() ?? '',
      userId: json['user_id']?.toString().trim() ?? '',
      email: _nullableString(json['email']),
      phone: _nullableString(json['phone']),
      firstName: _nullableString(json['first_name']),
      surname: _nullableString(json['surname']),
      documentNumber: json['document_number']?.toString().trim() ?? '',
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      principalLiquidated: NumberConversionService.toDouble(
        json['principal_liquidated'],
      ),
      interestLiquidated: NumberConversionService.toDouble(
        json['interest_liquidated'],
      ),
      totalLiquidated: NumberConversionService.toDouble(
        json['total_liquidated'],
      ),
      loanStatus: json['loan_status']?.toString().trim().toLowerCase() ?? '',
      liquidatedAt: _nullableDateTime(json['liquidated_at']),
    );
  }

  String get borrowerName {
    final names = [
      firstName,
      surname,
    ].whereType<String>().where((value) => value.isNotEmpty);

    if (names.isNotEmpty) {
      return names.join(' ');
    }

    return email ?? phone ?? userId;
  }

  String? get borrowerContact => email ?? phone;

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    return result == null || result.isEmpty ? null : result;
  }

  static DateTime? _nullableDateTime(dynamic value) {
    final raw = _nullableString(value);

    return raw == null ? null : DateTime.tryParse(raw);
  }
}

class LiquidatedLoansToday {
  LiquidatedLoansToday({
    required List<LiquidatedLoanRow> rows,
    required this.pagination,
  }) : rows = List.unmodifiable(rows);

  final List<LiquidatedLoanRow> rows;
  final ReportPagination pagination;

  factory LiquidatedLoansToday.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'];

    return LiquidatedLoansToday(
      rows: _parseRows(json['rows']),
      pagination: pagination is Map
          ? ReportPagination.fromJson(Map<String, dynamic>.from(pagination))
          : ReportPagination.empty(),
    );
  }

  factory LiquidatedLoansToday.empty() {
    return LiquidatedLoansToday(
      rows: const [],
      pagination: ReportPagination.empty(),
    );
  }

  bool get isEmpty => rows.isEmpty;

  bool get isNotEmpty => rows.isNotEmpty;

  int get pageLoanCount => rows.length;

  int get totalLoanCount => pagination.totalEntries;

  int get borrowerCount => rows.map((row) => row.userId).toSet().length;

  List<LiquidatedLoanRow> rowsForUser(String userId) {
    return List.unmodifiable(rows.where((row) => row.userId == userId));
  }

  Map<String, double> get totalLiquidatedByCurrency {
    final totals = <String, double>{};

    for (final row in rows) {
      final currency = row.currencyCode;

      if (currency.isEmpty) {
        continue;
      }

      totals[currency] = (totals[currency] ?? 0) + row.totalLiquidated;
    }

    return Map.unmodifiable(totals);
  }

  static List<LiquidatedLoanRow> _parseRows(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) => LiquidatedLoanRow.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }
}
