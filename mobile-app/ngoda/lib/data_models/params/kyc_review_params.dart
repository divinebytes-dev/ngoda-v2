class KycReviewQueueParams {
  KycReviewQueueParams({this.page = 1, this.pageSize = 20, String? countryCode})
    : countryCode = countryCode == null
          ? null
          : _normalizeCountryCode(countryCode);

  final int page;
  final int pageSize;
  final String? countryCode;

  KycReviewQueueParams copyWith({
    int? page,
    int? pageSize,
    String? countryCode,
    bool clearCountryCode = false,
  }) {
    return KycReviewQueueParams(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      countryCode: clearCountryCode ? null : countryCode ?? this.countryCode,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      'page': page,
      'pageSize': pageSize,
      if (countryCode != null && countryCode!.isNotEmpty)
        'countryCode': countryCode,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is KycReviewQueueParams &&
            other.page == page &&
            other.pageSize == pageSize &&
            other.countryCode == countryCode;
  }

  @override
  int get hashCode {
    return Object.hash(page, pageSize, countryCode);
  }

  static String _normalizeCountryCode(String value) {
    return value.trim().toLowerCase();
  }
}
