import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionService {
  AppPermissionService._();

  static bool _requestedThisSession = false;

  static const List<Permission> _corePermissions = [
    Permission.notification,
    Permission.locationWhenInUse,
    Permission.microphone,
  ];

  static Future<void> requestStartupPermissions() async {
    if (_requestedThisSession) return;
    _requestedThisSession = true;
    await requestCorePermissions();
  }

  static Future<bool> requestCorePermissions() async {
    if (kIsWeb) return true;

    for (final permission in _corePermissions) {
      try {
        final status = await permission.status;
        if (status.isDenied || status.isRestricted || status.isLimited) {
          await permission.request();
        }
      } catch (e) {
        debugPrint('Erro ao solicitar permissao ${permission.toString()}: $e');
      }
    }

    return hasCorePermissions();
  }

  static Future<bool> hasCorePermissions() async {
    if (kIsWeb) return true;

    final needsRuntimeNotificationPermission =
        defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS;
    final notificationOk = !needsRuntimeNotificationPermission ||
        await Permission.notification.isGranted;
    final locationOk = await Permission.locationWhenInUse.isGranted;
    final microphoneOk = await Permission.microphone.isGranted;

    return notificationOk && locationOk && microphoneOk;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
