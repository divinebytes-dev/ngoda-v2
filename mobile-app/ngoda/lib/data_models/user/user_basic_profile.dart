import 'package:ngoda/ui/enums/enums.dart';

class UserBasicProfile {
  const UserBasicProfile({
    required this.firstName,
    required this.middleName,
    required this.surname,
    required this.dateOfBirth,
    required this.gender,
    required this.nationality,
  });

  final String? firstName;

  final String? middleName;

  final String? surname;

  final DateTime? dateOfBirth;

  final GenderType? gender;

  final String? nationality;

  factory UserBasicProfile.fromJson(Map<String, dynamic> json) {
    final genderValue = _optionalString(json['gender']);

    return UserBasicProfile(
      firstName: _optionalString(json['first_name']),
      middleName: _optionalString(json['middle_name']),
      surname: _optionalString(json['surname']),
      dateOfBirth: _optionalDate(json['dob']),
      gender: genderValue == null ? null : GenderType.fromJson(genderValue),
      nationality: _optionalString(json['nationality']),
    );
  }

  UserBasicProfile copyWith({
    String? firstName,
    bool clearFirstName = false,
    String? middleName,
    bool clearMiddleName = false,
    String? surname,
    bool clearSurname = false,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    GenderType? gender,
    bool clearGender = false,
    String? nationality,
    bool clearNationality = false,
  }) {
    return UserBasicProfile(
      firstName: clearFirstName ? null : firstName ?? this.firstName,
      middleName: clearMiddleName ? null : middleName ?? this.middleName,
      surname: clearSurname ? null : surname ?? this.surname,
      dateOfBirth: clearDateOfBirth ? null : dateOfBirth ?? this.dateOfBirth,
      gender: clearGender ? null : gender ?? this.gender,
      nationality: clearNationality ? null : nationality ?? this.nationality,
    );
  }

  String get fullName {
    return <String>[?firstName, ?middleName, ?surname].join(' ');
  }

  bool get hasName => fullName.isNotEmpty;

  Map<String, dynamic> toQuery() {
    return {
      'firstName': firstName,
      'middleName': middleName,
      'surname': surname,
      'gender': gender?.apiValue,
      'nationality': nationality,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
    };
  }
}

String? _optionalString(dynamic value) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    return null;
  }

  return result;
}

DateTime? _optionalDate(dynamic value) {
  final raw = _optionalString(value);

  if (raw == null) {
    return null;
  }

  return DateTime.tryParse(raw);
}
