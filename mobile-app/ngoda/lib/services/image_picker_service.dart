import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  ImagePickerService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  static const int defaultImageQuality = 90;

  final ImagePicker _imagePicker;

  Future<XFile?> pickFromGallery({int imageQuality = defaultImageQuality}) {
    return _pickImage(source: ImageSource.gallery, imageQuality: imageQuality);
  }

  Future<XFile?> takePhoto({int imageQuality = defaultImageQuality}) {
    return _pickImage(source: ImageSource.camera, imageQuality: imageQuality);
  }

  Future<XFile?> _pickImage({
    required ImageSource source,
    required int imageQuality,
  }) async {
    try {
      return await _imagePicker.pickImage(
        source: source,
        imageQuality: imageQuality.clamp(0, 100),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ImagePickerServiceException(code: 'IMAGE_PICK_FAILED', cause: error),
        stackTrace,
      );
    }
  }

  Future<XFile?> retrieveLostImage() async {
    try {
      final response = await _imagePicker.retrieveLostData();

      if (response.isEmpty) {
        return null;
      }

      final exception = response.exception;

      if (exception != null) {
        throw ImagePickerServiceException(
          code: 'IMAGE_RECOVERY_FAILED',
          cause: exception,
        );
      }

      return response.file;
    } on ImagePickerServiceException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ImagePickerServiceException(
          code: 'IMAGE_RECOVERY_FAILED',
          cause: error,
        ),
        stackTrace,
      );
    }
  }
}

class ImagePickerServiceException implements Exception {
  const ImagePickerServiceException({required this.code, required this.cause});

  final String code;
  final Object cause;

  @override
  String toString() {
    return '$code: $cause';
  }
}
