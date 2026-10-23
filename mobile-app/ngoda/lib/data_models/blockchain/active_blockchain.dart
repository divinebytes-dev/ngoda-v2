import 'package:ngoda/services/number_conversion_service.dart';

class ActiveBlockchain {
  const ActiveBlockchain({
    required this.code,
    required this.name,
    required this.chainId,
    required this.networkName,
  });

  final String code;
  final String name;
  final int chainId;
  final String networkName;

  factory ActiveBlockchain.fromJson(Map<String, dynamic> json) {
    return ActiveBlockchain(
      code: (json['code'] ?? '').toString().trim().toLowerCase(),
      name: (json['name'] ?? '').toString().trim(),
      chainId: NumberConversionService.toInt(json['chain_id']),
      networkName: (json['network_name'] ?? '').toString().trim(),
    );
  }

  String get displayName {
    if (networkName.isEmpty) {
      return name;
    }

    return '$name ($networkName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ActiveBlockchain &&
            other.code == code &&
            other.chainId == chainId;
  }

  @override
  int get hashCode => Object.hash(code, chainId);
}
