class UserVerificationDocument {
  const UserVerificationDocument({
    required this.id,
    required this.url,
    required this.fileName,
    required this.status,
    required this.uploadedAt,
    required this.verifiedAt,
  });

  final String? id;

  final String? url;

  final String? fileName;

  /// Dynamic backend document status.
  final String? status;

  final DateTime? uploadedAt;

  final DateTime? verifiedAt;

  factory UserVerificationDocument.fromJson(Map<String, dynamic> json) {
    return UserVerificationDocument(
      id: _optionalString(json['id']),
      url: _optionalString(json['url']),
      fileName: _optionalString(json['file_name']),
      status: _optionalString(json['status'])?.toLowerCase(),
      uploadedAt: _optionalDateTime(json['uploaded_at']),
      verifiedAt: _optionalDateTime(json['verified_at']),
    );
  }

  bool get hasFile => url != null;

  bool get hasBeenUploaded => uploadedAt != null;

  bool get hasBeenVerified => verifiedAt != null;
}

String? _optionalString(dynamic value) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    return null;
  }

  return result;
}

DateTime? _optionalDateTime(dynamic value) {
  final raw = _optionalString(value);

  if (raw == null) {
    return null;
  }

  return DateTime.tryParse(raw);
}
