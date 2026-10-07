class GlDrilldownParams {
  GlDrilldownParams({required String gl, required String currency})
    : gl = gl.trim(),
      currency = currency.trim().toLowerCase();

  final String gl;
  final String currency;

  GlDrilldownParams copyWith({String? gl, String? currency}) {
    return GlDrilldownParams(
      gl: gl ?? this.gl,
      currency: currency ?? this.currency,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {'gl': gl, 'currency': currency};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GlDrilldownParams &&
            other.gl == gl &&
            other.currency == currency;
  }

  @override
  int get hashCode {
    return Object.hash(gl, currency);
  }
}
