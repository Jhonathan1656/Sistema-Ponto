import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class AppConfig {
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get backendUrl {
    return backendUrls.first;
  }

  static List<String> get backendUrls {
    if (_apiBaseUrl.isNotEmpty) return [_apiBaseUrl];
    if (kIsWeb) return ['${Uri.base.origin}/api'];
    if (defaultTargetPlatform == TargetPlatform.android) {
      return [
        'http://192.168.1.2:8080/api',
        'http://192.168.1.2:8000',
      ];
    }
    return ['http://localhost:8000'];
  }
}
