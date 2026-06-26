import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/admin_chat_list_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/documents_screen.dart';
import '../screens/home_screen.dart';

class AppNavigationService {
  AppNavigationService._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> openNotificationPayload(String? payload) async {
    if (payload == null || payload.isEmpty) return;

    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    } catch (_) {
      data = {'type': payload};
    }

    final type = data['type']?.toString();
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    if (type == 'signature_document') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const DocumentsScreen()),
      );
      return;
    }

    if (type == 'admin_chat_message') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const AdminChatListScreen()),
      );
      return;
    }

    if (type == 'chat_message') {
      final conversationId = data['conversation_id']?.toString() ?? '';
      if (conversationId.isEmpty) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            title: 'Ajuste de ponto',
          ),
        ),
      );
      return;
    }

    if (type == 'home' ||
        type == 'open_shift_24h' ||
        type == 'intern_open_point') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  static void openWhenReady(String? payload) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      openNotificationPayload(payload);
    });
  }
}
