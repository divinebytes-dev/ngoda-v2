import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/services/image_picker_service.dart';

final imagePickerServiceProvider = Provider<ImagePickerService>((ref) {
  return ImagePickerService();
});
