abstract final class NumberConversionService {
  static double toDouble(dynamic value, {double fallback = 0.0}) {
    return toNullableDouble(value) ?? fallback;
  }

  static double? toNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final normalized = value.trim();

      if (normalized.isEmpty) {
        return null;
      }

      return double.tryParse(normalized);
    }

    return null;
  }

  static int toInt(dynamic value, {int fallback = 0}) {
    return toNullableInt(value) ?? fallback;
  }

  static int? toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      final normalized = value.trim();

      if (normalized.isEmpty) {
        return null;
      }

      final integer = int.tryParse(normalized);

      if (integer != null) {
        return integer;
      }

      return double.tryParse(normalized)?.toInt();
    }

    return null;
  }

  static num toNum(dynamic value, {num fallback = 0}) {
    return toNullableNum(value) ?? fallback;
  }

  static num? toNullableNum(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value;
    }

    if (value is String) {
      final normalized = value.trim();

      if (normalized.isEmpty) {
        return null;
      }

      return num.tryParse(normalized);
    }

    return null;
  }
}
