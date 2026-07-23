import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_app/services/app_config.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android usa a API de producao por padrao', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    expect(
      AppConfig.backendUrl,
      'https://ponto.vmacengenharia.com/api',
    );
  });

  test('desktop usa o backend local por padrao', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    expect(AppConfig.backendUrl, 'http://localhost:8000');
  });
}
