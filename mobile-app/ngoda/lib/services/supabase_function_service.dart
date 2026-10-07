import 'package:logging/logging.dart';
import 'package:ngoda/ui/functions/extract_error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseFunctionService {
  SupabaseFunctionService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  final Logger _logger = Logger('SupabaseFunctionService');

  Future<Map<String, dynamic>> invoke({
    required String functionName,
    HttpMethod method = HttpMethod.post,
    Map<String, dynamic>? body,
    Map<String, Object?>? queryParameters,
    String invalidResponseMessage = 'Invalid function response',
  }) async {
    final response = await _invoke(
      functionName: functionName,
      method: method,
      body: body,
      queryParameters: queryParameters,
    );

    final data = response.data;

    if (data is! Map) {
      throw Exception(invalidResponseMessage);
    }

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> invokeData({
    required String functionName,
    HttpMethod method = HttpMethod.post,
    Map<String, dynamic>? body,
    Map<String, Object?>? queryParameters,
    String invalidResponseMessage = 'Invalid function response',
  }) async {
    final response = await invoke(
      functionName: functionName,
      method: method,
      body: body,
      queryParameters: queryParameters,
      invalidResponseMessage: invalidResponseMessage,
    );

    final data = response['data'];

    if (data is! Map) {
      throw Exception(invalidResponseMessage);
    }

    return Map<String, dynamic>.from(data);
  }

  Future<T> invokeValue<T>({
    required String functionName,
    HttpMethod method = HttpMethod.post,
    Map<String, dynamic>? body,
    Map<String, Object?>? queryParameters,
    String invalidResponseMessage = 'Invalid function response',
  }) async {
    final response = await invoke(
      functionName: functionName,
      method: method,
      body: body,
      queryParameters: queryParameters,
      invalidResponseMessage: invalidResponseMessage,
    );

    final data = response['data'];
    _logger.info("data $data");

    if (data is! T) {
      throw Exception(invalidResponseMessage);
    }

    return data;
  }

  Future<List<dynamic>> invokeList({
    required String functionName,
    HttpMethod method = HttpMethod.post,
    Map<String, dynamic>? body,
    Map<String, Object?>? queryParameters,
    String invalidResponseMessage = 'Invalid function response',
  }) async {
    final response = await invoke(
      functionName: functionName,
      method: method,
      body: body,
      queryParameters: queryParameters,
      invalidResponseMessage: invalidResponseMessage,
    );

    final data = response['data'];

    if (data is! List) {
      throw Exception(invalidResponseMessage);
    }

    return List<dynamic>.from(data);
  }

  Future<void> invokeVoid({
    required String functionName,
    HttpMethod method = HttpMethod.post,
    Map<String, dynamic>? body,
    Map<String, Object?>? queryParameters,
  }) async {
    await _invoke(
      functionName: functionName,
      method: method,
      body: body,
      queryParameters: queryParameters,
    );
  }

  Future<T> invokeDataValue<T>({
    required String functionName,
    HttpMethod method = HttpMethod.post,
    Map<String, dynamic>? body,
    Map<String, Object?>? queryParameters,
    String invalidResponseMessage = 'Invalid function response',
  }) async {
    final response = await invoke(
      functionName: functionName,
      method: method,
      body: body,
      queryParameters: queryParameters,
      invalidResponseMessage: invalidResponseMessage,
    );

    final data = response['data'];

    if (data is! T) {
      throw Exception(invalidResponseMessage);
    }

    return data;
  }

  Future<FunctionResponse> _invoke({
    required String functionName,
    required HttpMethod method,
    Map<String, dynamic>? body,
    Map<String, Object?>? queryParameters,
  }) async {
    try {
      final endpoint = _buildEndpoint(functionName, queryParameters);

      return await _supabase.functions.invoke(
        endpoint,
        method: method,
        body: body,
      );
    } on FunctionException catch (error) {
      _handleFunctionException(error, functionName: functionName);
    }
  }

  String _buildEndpoint(
    String functionName,
    Map<String, Object?>? queryParameters,
  ) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return functionName;
    }

    final parameters = <String, String>{};

    for (final entry in queryParameters.entries) {
      final value = entry.value;

      if (value != null) {
        parameters[entry.key] = value.toString();
      }
    }

    if (parameters.isEmpty) {
      return functionName;
    }

    final query = Uri(queryParameters: parameters).query;

    return '$functionName?$query';
  }

  Never _handleFunctionException(
    FunctionException error, {
    required String functionName,
  }) {
    final message = extractFunctionError(error);

    _logger.info('$functionName function error: $message');

    throw Exception(message);
  }
}
