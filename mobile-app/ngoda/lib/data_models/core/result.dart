class R<T> {
  const R({this.result, this.error});

  final T? result;

  final String? error;

  bool get hasError => error != null;

  bool get hasResult => result != null;

  bool get isSuccess => !hasError;
}
