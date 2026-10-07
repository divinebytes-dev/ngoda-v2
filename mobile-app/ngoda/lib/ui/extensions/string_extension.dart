extension StringExtension on String {
  String capitalize() {
    if (isEmpty) {
      return '';
    }

    return '${this[0].toUpperCase()}${substring(1)}';
  }

  String capitalizeWords() {
    return trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String get initials {
    final words = trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return '';
    }

    if (words.length == 1) {
      return words.first[0].toUpperCase();
    }

    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  bool get isBlank {
    return trim().isEmpty;
  }

  bool get isNotBlank {
    return trim().isNotEmpty;
  }
}
