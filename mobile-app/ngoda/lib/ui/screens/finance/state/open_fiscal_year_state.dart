class OpenFiscalYearState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;

  const OpenFiscalYearState({
    this.isLoading = false,
    this.error,
    this.isSuccess = false,
  });

  OpenFiscalYearState copyWith({
    bool? isLoading,
    String? error,
    bool? isSuccess,
    bool clearError = false,
  }) {
    return OpenFiscalYearState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}
