import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';

abstract final class TransactionQrCodecService {
  static String encode(TransactionData transaction) {
    final json = jsonEncode(transaction.toJson());

    final compressed = GZipEncoder().encode(utf8.encode(json));

    return base64Encode(compressed);
  }

  static TransactionData decode(String value) {
    final compressed = base64Decode(value.trim());

    final decompressed = GZipDecoder().decodeBytes(compressed);

    final decoded = utf8.decode(decompressed);

    final json = jsonDecode(decoded);

    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid transaction QR payload.');
    }

    return TransactionData.fromJson(json);
  }
}
