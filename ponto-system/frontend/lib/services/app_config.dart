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
        'https://ponto.vmacengenharia.com/api',
        'http://ponto.vmacengenharia.com/api',
      ];
    }
    return ['http://localhost:8000'];
  }
}
