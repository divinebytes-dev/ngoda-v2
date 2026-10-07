import 'package:ngoda/services/supabase_function_service.dart';

class AgentApiService {
  const AgentApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<Map<String, dynamic>> getDashboard() async {
    return _functions.invokeData(
      functionName: 'agent-dashboard',
      invalidResponseMessage: 'Invalid agent dashboard response',
    );
  }
}
