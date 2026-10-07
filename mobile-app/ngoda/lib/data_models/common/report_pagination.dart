import 'package:ngoda/services/number_conversion_service.dart';

class ReportPagination {
  const ReportPagination({
    required this.page,
    required this.pageSize,
    required this.totalEntries,
    required this.totalPages,
    required this.hasPrevious,
    required this.hasNext,
  });

  final int page;
  final int pageSize;

  final int totalEntries;
  final int totalPages;

  final bool hasPrevious;
  final bool hasNext;

  factory ReportPagination.fromJson(Map<String, dynamic> json) {
    return ReportPagination(
      page: NumberConversionService.toNullableInt(json['page']) ?? 1,
      pageSize: NumberConversionService.toNullableInt(json['page_size']) ?? 50,
      totalEntries:
          NumberConversionService.toNullableInt(json['total_entries']) ?? 0,
      totalPages:
          NumberConversionService.toNullableInt(json['total_pages']) ?? 1,
      hasPrevious: json['has_previous'] == true,
      hasNext: json['has_next'] == true,
    );
  }

  factory ReportPagination.empty() {
    return const ReportPagination(
      page: 1,
      pageSize: 50,
      totalEntries: 0,
      totalPages: 1,
      hasPrevious: false,
      hasNext: false,
    );
  }
}
