import 'dart:async';

import 'package:app_links/app_links.dart';

class DeepLinkService {
  static const String _referralHost = 'app.ngoda.com';

  static const String _referralPath = 'ref';

  final AppLinks _appLinks = AppLinks();

  StreamSubscription<Uri>? _subscription;

  bool get isInitialized {
    return _subscription != null;
  }

  Future<void> initialize({
    required Future<void> Function(Uri uri) onLinkReceived,
  }) async {
    await _subscription?.cancel();

    _subscription = _appLinks.uriLinkStream.listen((uri) {
      unawaited(onLinkReceived(uri));
    });
  }

  Future<Uri?> getInitialLink() {
    return _appLinks.getInitialLink();
  }

  String? extractReferralCode(Uri uri) {
    /*
     * Universal/App Link:
     *
     * https://app.ngoda.com/ref/TEST123
     */
    if (_isReferralWebLink(uri)) {
      return _normalizeReferralCode(uri.pathSegments[1]);
    }

    /*
     * Custom scheme:
     *
     * ngoda://ref/TEST123
     */
    if (_isReferralCustomLink(uri)) {
      return _normalizeReferralCode(uri.pathSegments.first);
    }

    return null;
  }

  Uri buildReferralUri(String referralCode) {
    final code = referralCode.trim();

    if (code.isEmpty) {
      throw const FormatException('Referral code cannot be empty.');
    }

    return Uri(
      scheme: 'https',
      host: _referralHost,
      pathSegments: [_referralPath, code],
    );
  }

  String buildReferralLink(String referralCode) {
    return buildReferralUri(referralCode).toString();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();

    _subscription = null;
  }

  bool _isReferralWebLink(Uri uri) {
    return (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.toLowerCase() == _referralHost &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first.toLowerCase() == _referralPath;
  }

  bool _isReferralCustomLink(Uri uri) {
    return uri.scheme.toLowerCase() == 'ngoda' &&
        uri.host.toLowerCase() == _referralPath &&
        uri.pathSegments.isNotEmpty;
  }

  String? _normalizeReferralCode(String value) {
    final code = value.trim();

    if (code.isEmpty) {
      return null;
    }

    return code;
  }
}
