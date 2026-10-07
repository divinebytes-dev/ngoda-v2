import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/services/share_service.dart';

final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService();
});
