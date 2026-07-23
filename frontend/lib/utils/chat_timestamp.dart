import 'package:cloud_firestore/cloud_firestore.dart';

DateTime chatMessageTime(Map<String, dynamic> message) {
  return _dateTimeFrom(
    message['created_at'],
    fallback: message['timestamp'],
  );
}

DateTime chatConversationTime(Map<String, dynamic> conversation) {
  return _dateTimeFrom(
    conversation['last_server_at'],
    fallback: conversation['last_time'],
  );
}

int compareChatMessages(
  Map<String, dynamic> first,
  Map<String, dynamic> second,
) {
  final byTime = chatMessageTime(first).compareTo(chatMessageTime(second));
  if (byTime != 0) return byTime;
  return (first['id']?.toString() ?? '')
      .compareTo(second['id']?.toString() ?? '');
}

DateTime _dateTimeFrom(dynamic value, {dynamic fallback}) {
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is DateTime) return value.toLocal();

  final parsedValue = DateTime.tryParse(value?.toString() ?? '');
  if (parsedValue != null) return parsedValue.toLocal();

  final parsedFallback = DateTime.tryParse(fallback?.toString() ?? '');
  if (parsedFallback != null) return parsedFallback.toLocal();

  return DateTime.fromMillisecondsSinceEpoch(0);
}
