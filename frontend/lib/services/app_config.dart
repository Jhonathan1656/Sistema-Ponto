import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class AppConfig {
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _productionApiBaseUrl =
      'https://ponto.vmacengenharia.com/api';

  static String get backendUrl {
    if (_apiBaseUrl.trim().isNotEmpty) {
      return _withoutTrailingSlash(_apiBaseUrl.trim());
    }

    if (kIsWeb) {
      return '${Uri.base.origin}/api';
    }

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return _productionApiBaseUrl;
    }

    return 'http://localhost:8000';
  }

  static String _withoutTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
