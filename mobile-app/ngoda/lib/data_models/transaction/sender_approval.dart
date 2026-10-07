class SenderApproval {
  SenderApproval({
    required this.v,
    required this.r,
    required this.b,
    required this.a,
    required String c,
    required this.bs,
  }) : c = c.trim().toLowerCase();

  /// Protocol version.
  final String v;

  /// Transaction reference.
  final String r;

  /// Buyer/user identifier.
  final String b;

  /// Approval timestamp.
  final int a;

  /// Currency code.
  final String c;

  /// Buyer signature.
  final String bs;

  String get version => v;

  String get reference => r;

  String get buyerId => b;

  int get approvedAt => a;

  String get currencyCode => c;

  String get buyerSignature => bs;

  String canonicalString(String approvalVersion) {
    return ['approval_$approvalVersion', r, b, a.toString(), c].join('|');
  }

  Map<String, dynamic> toJson() {
    return {'v': v, 'r': r, 'b': b, 'a': a, 'c': c, 'bs': bs};
  }

  factory SenderApproval.fromJson(Map<String, dynamic> json) {
    return SenderApproval(
      v: _requiredString(json['v'], 'v'),
      r: _requiredString(json['r'], 'r'),
      b: _requiredString(json['b'], 'b'),
      a: _requiredInt(json['a'], 'a'),
      c: _requiredString(json['c'], 'c'),
      bs: _requiredString(json['bs'], 'bs'),
    );
  }

  static String _requiredString(dynamic value, String field) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      throw FormatException('SenderApproval.$field is required.');
    }

    return result;
  }

  static int _requiredInt(dynamic value, String field) {
    if (value is int) {
      return value;
    }

    final result = int.tryParse(value?.toString() ?? '');

    if (result == null) {
      throw FormatException('SenderApproval.$field is invalid.');
    }

    return result;
  }
}
