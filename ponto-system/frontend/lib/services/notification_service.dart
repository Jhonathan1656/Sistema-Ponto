import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const int _internReminderId = 1002;

  static const AndroidNotificationChannel _breakChannel =
      AndroidNotificationChannel(
    'break_auto_close',
    'Fechamento de pausas',
    description: 'Avisos quando uma pausa e fechada automaticamente.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _internReminderChannel =
      AndroidNotificationChannel(
    'intern_open_point_reminder',
    'Lembretes de ponto aberto',
    description: 'Avisos para estagiarios com ponto aberto no horario limite.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> initialize() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

    const androidSettings = AndroidInitializationSettings('notification_icon');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings: initializationSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_breakChannel);
    await androidPlugin?.createNotificationChannel(_internReminderChannel);
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> showBreakAutoClosed({
    required DateTime closedAt,
  }) async {
    final time = DateFormat('HH:mm:ss').format(closedAt);

    const androidDetails = AndroidNotificationDetails(
      'break_auto_close',
      'Fechamento de pausas',
      channelDescription: 'Avisos quando uma pausa e fechada automaticamente.',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ticker: 'Pausa fechada automaticamente',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      id: 1001,
      title: 'Pausa fechada automaticamente',
      body:
          'Provavelmente voce esqueceu a pausa aberta. Fechando a pausa $time e retomando o turno.',
      notificationDetails: details,
    );
  }

  static Future<void> showInternOpenPointReminder() async {
    const androidDetails = AndroidNotificationDetails(
      'intern_open_point_reminder',
      'Lembretes de ponto aberto',
      channelDescription:
          'Avisos para estagiarios com ponto aberto no horario limite.',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ticker: 'Talvez voce tenha esquecido o ponto aberto',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      id: _internReminderId,
      title: 'Ponto aberto',
      body:
          'Talvez voce tenha esquecido de fechar o ponto. Se ainda estiver trabalhando, pode ignorar.',
      notificationDetails: details,
    );
  }

  static Future<void> scheduleInternOpenPointReminder(
      DateTime reference) async {
    final scheduledAt = DateTime(
      reference.year,
      reference.month,
      reference.day,
      19,
      35,
    );

    await cancelInternOpenPointReminder();
    if (!scheduledAt.isAfter(reference)) return;

    const androidDetails = AndroidNotificationDetails(
      'intern_open_point_reminder',
      'Lembretes de ponto aberto',
      channelDescription:
          'Avisos para estagiarios com ponto aberto no horario limite.',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ticker: 'Talvez voce tenha esquecido o ponto aberto',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.zonedSchedule(
      id: _internReminderId,
      title: 'Ponto aberto',
      body:
          'Talvez voce tenha esquecido de fechar o ponto. Se ainda estiver trabalhando, pode ignorar.',
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancelInternOpenPointReminder() async {
    await _plugin.cancel(id: _internReminderId);
  }
}
