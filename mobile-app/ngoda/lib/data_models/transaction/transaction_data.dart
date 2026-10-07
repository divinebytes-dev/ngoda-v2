import 'dart:convert';

class TransactionData {
  TransactionData({
    required this.v,
    required this.r,
    required this.s,
    required this.a,
    required this.f,
    required this.g,
    required String c,
    required this.t,
    required this.e,
    this.ms,
  }) : c = c.trim().toLowerCase();

  /// Protocol version.
  final String v;

  /// Transaction reference.
  final String r;

  /// Seller/receiver identifier.
  final String s;

  /// Amount in protocol minor units.
  final int a;

  /// Fee in protocol minor units.
  final int f;

  /// Government tax in protocol minor units.
  final int g;

  /// Currency code.
  final String c;

  /// Transaction timestamp.
  final int t;

  /// Expiry timestamp.
  final int e;

  /// Merchant signature.
  final String? ms;

  String get version => v;

  String get reference => r;

  String get sellerId => s;

  int get amountMinor => a;

  int get feeMinor => f;

  int get governmentTaxMinor => g;

  String get currencyCode => c;

  int get timestamp => t;

  int get expiresAt => e;

  String? get merchantSignature => ms;

  String canonicalString() {
    return [
      v,
      r,
      s,
      a.toString(),
      f.toString(),
      g.toString(),
      c,
      t.toString(),
      e.toString(),
    ].join('|');
  }

  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'r': r,
      's': s,
      'a': a,
      'f': f,
      'g': g,
      'c': c,
      't': t,
      'e': e,
      'ms': ms,
    };
  }

  factory TransactionData.fromJson(Map<String, dynamic> json) {
    return TransactionData(
      v: _requiredString(json['v'], 'v'),
      r: _requiredString(json['r'], 'r'),
      s: _requiredString(json['s'], 's'),
      a: _requiredInt(json['a'], 'a'),
      f: _requiredInt(json['f'], 'f'),
      g: _requiredInt(json['g'], 'g'),
      c: _requiredString(json['c'], 'c'),
      t: _requiredInt(json['t'], 't'),
      e: _requiredInt(json['e'], 'e'),
      ms: _nullableString(json['ms']),
    );
  }

  String toQrString() {
    return jsonEncode(toJson());
  }

  static String _requiredString(dynamic value, String field) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      throw FormatException('TransactionData.$field is required.');
    }

    return result;
  }

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      return null;
    }

    return result;
  }

  static int _requiredInt(dynamic value, String field) {
    if (value is int) {
      return value;
    }

    final result = int.tryParse(value?.toString() ?? '');

    if (result == null) {
      throw FormatException('TransactionData.$field is invalid.');
    }

    return result;
  }
}
