import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/services/permission_handler_service.dart';

final permissionHandlerServiceProvider = Provider<PermissionHandlerService>((
  ref,
) {
  return PermissionHandlerService();
});
