import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/admin_chat_list_screen.dart';
import '../screens/chat_screen.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

class UserNotificationBell extends StatefulWidget {
  final bool isAdmin;

  const UserNotificationBell({super.key, this.isAdmin = false});

  @override
  State<UserNotificationBell> createState() => _UserNotificationBellState();
}

class _UserNotificationBellState extends State<UserNotificationBell> {
  static const _wineColor = Color(0xFF8B0000);
  final _apiService = ApiService();
  List<Map<String, dynamic>> _documentNotifications = [];
  final Set<String> _seenDocumentNotificationIds = {};
  bool _documentNotificationsInitialized = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadDocumentNotifications();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadDocumentNotifications(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDocumentNotifications() async {
    if (widget.isAdmin) return;

    try {
      final notifications = await _apiService.getSignatureNotifications();
      final unread = notifications
          .where((notification) => notification['is_read'] != 1)
          .toList();
      final newUnread = unread.where((notification) {
        final id = notification['id']?.toString();
        return id != null && !_seenDocumentNotificationIds.contains(id);
      }).toList();

      _seenDocumentNotificationIds
        ..clear()
        ..addAll(unread
            .map((notification) => notification['id']?.toString())
            .whereType<String>());

      if (_documentNotificationsInitialized && newUnread.isNotEmpty) {
        await NotificationService.showSignatureRequest(
          pendingCount: newUnread.length,
          title: newUnread.first['title']?.toString() ?? 'Documento',
        );
      }
      _documentNotificationsInitialized = true;

      if (mounted) setState(() => _documentNotifications = notifications);
    } catch (_) {
      // O sino continua exibindo as mensagens mesmo se a API estiver offline.
    }
  }

  Stream<List<Map<String, dynamic>>> _unreadChatMessages() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    final query = FirebaseFirestore.instance.collection('adjustment_requests');

    if (widget.isAdmin) {
      return query
          .where('sender_role', isEqualTo: 'user')
          .where('status', isEqualTo: 'unread')
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList());
    }

    return query.where('user_id', isEqualTo: user.uid).snapshots().map(
        (snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .where((message) =>
                message['sender_role'] == 'admin' &&
                message['notification_read'] != true)
            .toList());
  }

  Future<void> _openNotifications(
      List<Map<String, dynamic>> chatMessages) async {
    final unreadDocuments = widget.isAdmin
        ? <Map<String, dynamic>>[]
        : _documentNotifications
            .where((notification) => notification['is_read'] != 1)
            .toList();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('Notificacoes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (chatMessages.isEmpty && unreadDocuments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('Nenhuma notificacao nova.')),
                ),
              ...chatMessages.map((message) => ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x1A8B0000),
                      child: Icon(Icons.chat_outlined, color: _wineColor),
                    ),
                    title: Text(widget.isAdmin
                        ? 'Mensagem de ${message['user_name']?.toString() ?? 'colaborador'}'
                        : 'Resposta da gestao'),
                    subtitle: Text(message['message']?.toString() ?? 'Audio'),
                    onTap: () async {
                      if (!widget.isAdmin) {
                        await FirebaseFirestore.instance
                            .collection('adjustment_requests')
                            .doc(message['id'])
                            .update({'notification_read': true});
                      }
                      if (!mounted || !context.mounted) return;
                      Navigator.pop(context);
                      Navigator.of(this.context).push(
                        MaterialPageRoute(
                          builder: (_) => widget.isAdmin
                              ? const AdminChatListScreen()
                              : ChatScreen(
                                  conversationId:
                                      message['conversation_id']?.toString() ??
                                          '',
                                  title: 'Ajuste de ponto',
                                ),
                        ),
                      );
                    },
                  )),
              ...unreadDocuments.map((notification) => ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x1A8B0000),
                      child:
                          Icon(Icons.description_outlined, color: _wineColor),
                    ),
                    title:
                        Text(notification['title']?.toString() ?? 'Documento'),
                    subtitle: Text(notification['body']?.toString() ?? ''),
                  )),
            ],
          ),
        ),
      ),
    );

    if (unreadDocuments.isNotEmpty) {
      await _apiService.markSignatureNotificationsRead();
      await _loadDocumentNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _unreadChatMessages(),
      initialData: const [],
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        final unreadDocuments = widget.isAdmin
            ? 0
            : _documentNotifications
                .where((notification) => notification['is_read'] != 1)
                .length;
        final total = messages.length + unreadDocuments;

        return IconButton(
          tooltip: 'Notificacoes',
          onPressed: () => _openNotifications(messages),
          icon: Badge(
            isLabelVisible: total > 0,
            label: Text(total.toString()),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: _wineColor,
              size: 28,
            ),
          ),
        );
      },
    );
  }
}
