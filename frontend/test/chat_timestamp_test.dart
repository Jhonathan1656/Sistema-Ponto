import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_app/utils/chat_timestamp.dart';

void main() {
  test('horario do servidor prevalece sobre relogios locais divergentes', () {
    final adminReply = <String, dynamic>{
      'id': 'admin-reply',
      'timestamp': '2026-07-17T16:03:30',
      'created_at': Timestamp.fromMillisecondsSinceEpoch(1000),
    };
    final laterUserMessage = <String, dynamic>{
      'id': 'user-message',
      'timestamp': '2026-07-17T16:02:10',
      'created_at': Timestamp.fromMillisecondsSinceEpoch(2000),
    };

    final messages = [laterUserMessage, adminReply]..sort(compareChatMessages);

    expect(messages.map((message) => message['id']), [
      'admin-reply',
      'user-message',
    ]);
  });

  test('mensagens antigas continuam usando timestamp local', () {
    final messages = <Map<String, dynamic>>[
      {'id': 'second', 'timestamp': '2026-07-17T16:02:20'},
      {'id': 'first', 'timestamp': '2026-07-17T16:02:10'},
    ]..sort(compareChatMessages);

    expect(messages.map((message) => message['id']), ['first', 'second']);
  });
}
