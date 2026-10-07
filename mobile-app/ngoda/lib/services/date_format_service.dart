class DateFormatService {
  static const String fallback = '-';

  static String formatDateTime(dynamic dateInput) {
    return _formatSmart(dateInput);
  }

  static String formatCronJobDateTime(dynamic dateInput) {
    final date = _parseDate(dateInput);

    if (date == null) {
      return fallback;
    }

    return '${_day(date)} '
        '${_monthShort(date.month)} '
        '${date.year} '
        '${_time(date)}';
  }

  static String formatDateOnly(dynamic dateInput) {
    final date = _parseDate(dateInput);

    if (date == null) {
      return fallback;
    }

    final year = (date.year % 100).toString().padLeft(2, '0');

    return '${_day(date)} '
        '${_monthShort(date.month)} '
        '$year';
  }

  static String formatDisplayDate(dynamic dateInput) {
    final date = _parseDate(dateInput);

    if (date == null) {
      return fallback;
    }

    return '${_day(date)} '
        '${_monthShort(date.month)} '
        '${date.year}';
  }

  static String formatQueryDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDate(dynamic input) {
    if (input == null) {
      return null;
    }

    if (input is DateTime) {
      return input.isUtc ? input.toLocal() : input;
    }

    if (input is String) {
      final parsed = DateTime.tryParse(input.trim());

      if (parsed == null) {
        return null;
      }

      return parsed.isUtc ? parsed.toLocal() : parsed;
    }

    return null;
  }

  static String _formatSmart(dynamic input) {
    final date = _parseDate(input);

    if (date == null) {
      return fallback;
    }

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final yesterday = today.subtract(const Duration(days: 1));

    final target = DateTime(date.year, date.month, date.day);

    if (target == today) {
      return 'Today ${_time(date)}';
    }

    if (target == yesterday) {
      return 'Yesterday ${_time(date)}';
    }

    if (date.year == now.year) {
      return '${_day(date)} '
          '${_monthShort(date.month)} '
          '${_time(date)}';
    }

    return '${_day(date)} '
        '${_monthShort(date.month)} '
        '${date.year} '
        '${_time(date)}';
  }

  static String _day(DateTime date) {
    return date.day.toString().padLeft(2, '0');
  }

  static String _time(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  static String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return months[month - 1];
  }
}
