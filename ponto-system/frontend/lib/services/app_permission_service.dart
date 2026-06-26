import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionService {
  AppPermissionService._();

  static bool _requestedThisSession = false;

  static const List<Permission> _requiredPermissions = [
    Permission.locationWhenInUse,
    Permission.microphone,
  ];

  static const List<Permission> _startupPermissions = [
    Permission.notification,
    ..._requiredPermissions,
  ];

  static Future<void> requestStartupPermissions() async {
    if (_requestedThisSession) return;
    _requestedThisSession = true;
    await requestCorePermissions();
  }

  static Future<bool> requestCorePermissions() async {
    if (kIsWeb) return true;

    try {
      final pendingPermissions = <Permission>[];
      for (final permission in _startupPermissions) {
        final status = await permission.status;
        if (status.isDenied || status.isRestricted || status.isLimited) {
          pendingPermissions.add(permission);
        }
      }
      if (pendingPermissions.isNotEmpty) {
        await pendingPermissions.request();
      }
    } catch (e) {
      debugPrint('Erro ao solicitar permissoes: $e');
    }

    return hasCorePermissions();
  }

  static Future<bool> hasCorePermissions() async {
    if (kIsWeb) return true;

    final locationOk = await Permission.locationWhenInUse.isGranted;
    final microphoneOk = await Permission.microphone.isGranted;

    return locationOk && microphoneOk;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
