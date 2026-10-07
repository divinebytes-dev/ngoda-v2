import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/data_models/kyc/user_kyc_details.dart';
import 'package:ngoda/data_models/user/user_basic_profile.dart';
import 'package:ngoda/data_models/user/user_contact_details.dart';
import 'package:ngoda/data_models/user/user_details.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/functions/extract_error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserDetailsApiService {
  UserDetailsApiService(this._functions);

  final SupabaseFunctionService _functions;

  final SupabaseClient _supabase = Supabase.instance.client;

  final Logger _logger = Logger('UserDetailsApiService');

  Future<UserDetails> fetchUserDetails() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-user-details',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid user details response',
    );

    return UserDetails.fromJson(data);
  }

  Future<void> updateUserDetails({
    required UserBasicProfile userBasicProfile,
  }) async {
    await _functions.invokeVoid(
      functionName: 'upsert-my-user-basic-profile',
      body: userBasicProfile.toQuery(),
    );
  }

  Future<void> updateUserContacts({
    required UserContactDetails userContacts,
  }) async {
    await _functions.invokeVoid(
      functionName: 'upsert-user-contacts-details',
      body: userContacts.toQuery(),
    );
  }

  Future<void> updateUserKyc({required UserKycDetails userKyc}) async {
    await _functions.invokeVoid(
      functionName: 'upsert-user-kyc-details',
      body: userKyc.toQuery(),
    );
  }

  Future<void> updateDocumentVerification({
    required XFile file,
    required VerificationDocumentType type,
  }) async {
    try {
      final fileBytes = await file.readAsBytes();

      final mimeType = _resolveMimeType(file);

      final boundary = '----ngoda-${DateTime.now().microsecondsSinceEpoch}';

      final body = _buildMultipartBody(
        boundary: boundary,
        documentType: type.apiValue,
        fileName: file.name,
        mimeType: mimeType,
        fileBytes: fileBytes,
      );

      await _supabase.functions.invoke(
        'upsert-user-document-verification',
        body: body,
        headers: {
          'Content-Type':
              'multipart/form-data; '
              'boundary=$boundary',
        },
      );
    } on FunctionException catch (error) {
      final message = extractFunctionError(error);

      _logger.info(
        'upsert-user-document-verification '
        'function error: $message',
      );

      throw Exception(message);
    } catch (error) {
      throw Exception('ERROR: $error');
    }
  }

  Future<void> resetPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _functions.invokeVoid(
      functionName: 'change-user-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  Uint8List _buildMultipartBody({
    required String boundary,
    required String documentType,
    required String fileName,
    required String mimeType,
    required Uint8List fileBytes,
  }) {
    final bytes = <int>[];

    void writeString(String value) {
      bytes.addAll(utf8.encode(value));
    }

    writeString('--$boundary\r\n');

    writeString(
      'Content-Disposition: form-data; '
      'name="documentType"\r\n\r\n',
    );

    writeString('$documentType\r\n');

    writeString('--$boundary\r\n');

    writeString(
      'Content-Disposition: form-data; '
      'name="file"; '
      'filename="${_escapeFileName(fileName)}"\r\n',
    );

    writeString('Content-Type: $mimeType\r\n\r\n');

    bytes.addAll(fileBytes);

    writeString('\r\n--$boundary--\r\n');

    return Uint8List.fromList(bytes);
  }

  String _resolveMimeType(XFile file) {
    final suppliedMimeType = file.mimeType?.trim().toLowerCase();

    if (suppliedMimeType != null && suppliedMimeType.isNotEmpty) {
      return suppliedMimeType;
    }

    final fileName = file.name.toLowerCase();

    if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }

    if (fileName.endsWith('.png')) {
      return 'image/png';
    }

    if (fileName.endsWith('.webp')) {
      return 'image/webp';
    }

    if (fileName.endsWith('.pdf')) {
      return 'application/pdf';
    }

    return 'application/octet-stream';
  }

  String _escapeFileName(String value) {
    return value
        .replaceAll('\\', '_')
        .replaceAll('"', '_')
        .replaceAll('\r', '_')
        .replaceAll('\n', '_');
  }
}
