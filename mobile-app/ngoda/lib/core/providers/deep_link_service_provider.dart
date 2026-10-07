import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/services/deep_link_service.dart';

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService();
});
