import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

import 'user_chat_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _apiService = ApiService();
  String _currentTime = "";
  String _currentDate = "";
  bool _isLoading = true;
  List<dynamic> _todayRecords = [];
  String _currentStatus = "Carregando...";
  String _lastActionTime = "";
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Map<String, dynamic>? _user;
  bool _isAutoClosingBreak = false;
  bool _isSyncingOffline = false;
  int _pendingOfflineRecordsCount = 0;
  DateTime? _lastOfflineSyncAttempt;
  String? _lastInternReminderDate;

  // Cores da Empresa
  static const Color wineColor = Color(0xFF8B0000);

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (timer) => _updateTime());
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        unawaited(_trySyncOfflineRecords(showMessage: true));
      }
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('HH:mm:ss').format(now);
        _currentDate =
            DateFormat('EEEE, d MMMM yyyy', 'pt_BR').format(now).toUpperCase();
      });
      _checkAutoActions(now);
      if (_user != null &&
          (_lastOfflineSyncAttempt == null ||
              now.difference(_lastOfflineSyncAttempt!).inSeconds >= 30)) {
        _lastOfflineSyncAttempt = now;
        unawaited(_trySyncOfflineRecords());
      }
    }
  }

  void _checkAutoActions(DateTime now) {
    // 1. Fechamento automatico de pausa apos 1h30 aberta.
    if (_todayRecords.isNotEmpty && !_isAutoClosingBreak) {
      final last = _todayRecords.last;
      if (last['record_type'] == 'break_start' ||
          last['record_type'] == 'entry_3') {
        final startTime = DateTime.parse(last['timestamp']);
        final diff = now.difference(startTime).inMinutes;

        if (diff >= 90) {
          _autoCloseBreak(last['record_type'], startTime);
        }
      }
    }

    // 2. Aviso de horario para estagiarios (19:35)
    bool isEstagiario = _isInternUser;

    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    if (isEstagiario &&
        now.hour == 19 &&
        now.minute == 35 &&
        _lastInternReminderDate != todayKey) {
      _lastInternReminderDate = todayKey;
      unawaited(_notifyInternIfPointIsOpen());
    }
  }

  Future<void> _autoCloseBreak(String lastType, DateTime startTime) async {
    final String returnType =
        lastType == 'break_start' ? 'break_end' : 'exit_3';
    final closedAt = startTime.add(const Duration(hours: 1));
    final autoTime = closedAt.toIso8601String();

    try {
      _isAutoClosingBreak = true;
      await _apiService.createTimeRecord(
        recordType: returnType,
        timestamp: autoTime,
        notes: "Retorno automatico (pausa excedeu 1h30; ajustado para 1h)",
        location: "Sistema (Auto)",
      );
      await NotificationService.showBreakAutoClosed(closedAt: closedAt);
      await _loadTodayRecords();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pausa Encerrada'),
            content: const Text(
                'Sua pausa excedeu 1h30 e foi fechada automaticamente com 1 hora de pausa.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'))
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro no auto-close: $e');
    } finally {
      _isAutoClosingBreak = false;
    }
  }

  bool get _isInternUser {
    final role = (_user?['role'] ?? '').toString().toLowerCase();
    return role.contains('estag') || role.contains('intern');
  }

  bool get _hasOpenPoint {
    if (_todayRecords.isEmpty) return false;
    final last = _todayRecords.last['record_type']?.toString();
    return last != null && last != 'check_out';
  }

  Future<void> _configureInternReminder() async {
    if (!_isInternUser || !_hasOpenPoint) {
      await NotificationService.cancelInternOpenPointReminder();
      return;
    }

    await NotificationService.scheduleInternOpenPointReminder(DateTime.now());
  }

  Future<void> _notifyInternIfPointIsOpen() async {
    await _loadTodayRecords();
    if (!_isInternUser || !_hasOpenPoint) return;

    await NotificationService.showInternOpenPointReminder();
    if (mounted) _showOvertimeAlert();
  }

  String get _displayUserName {
    final name = (_user?['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final email = (_user?['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;

    return 'Carregando...';
  }

  void _showOvertimeAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Horário Encerrado'),
        content: const Text(
            'Já passou das 19:35! Lembre-se de registrar sua saída caso tenha finalizado o expediente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendi', style: TextStyle(color: wineColor))),
        ],
      ),
    );
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _apiService.getCurrentUser();
      _user = user;
      await _trySyncOfflineRecords();
      await _loadTodayRecords();
    } catch (e) {
      debugPrint('Erro init: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTodayRecords() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toIso8601String();
      final end =
          DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

      final records =
          await _apiService.getTimeRecords(startDate: start, endDate: end);
      final pendingRecords = await _apiService.getOfflineRecords();

      setState(() {
        _todayRecords = records.reversed.toList(); // Ordem cronológica
        _pendingOfflineRecordsCount = pendingRecords.length;
        _updateStatus();
      });
      unawaited(_configureInternReminder());
    } catch (e) {
      debugPrint('Erro records: $e');
    }
  }

  Future<void> _trySyncOfflineRecords({bool showMessage = false}) async {
    if (_isSyncingOffline) return;
    _isSyncingOffline = true;

    try {
      final syncedCount = await _apiService.syncOfflineRecords();
      final pendingRecords = await _apiService.getOfflineRecords();

      if (mounted) {
        setState(() => _pendingOfflineRecordsCount = pendingRecords.length);
      }

      if (syncedCount > 0) {
        await _loadTodayRecords();
        if (mounted && showMessage) {
          _showSuccess('$syncedCount registro(s) offline sincronizado(s).');
        }
      }
    } catch (e) {
      debugPrint('Erro ao sincronizar pontos offline: $e');
    } finally {
      _isSyncingOffline = false;
    }
  }

  void _updateStatus() {
    if (_todayRecords.isEmpty) {
      _currentStatus = "Aguardando entrada";
      _lastActionTime = "";
      return;
    }

    final last = _todayRecords.last;
    final time =
        DateFormat('HH:mm:ss').format(DateTime.parse(last['timestamp']));
    _lastActionTime = "desde $time";

    switch (last['record_type']) {
      case 'check_in':
        _currentStatus = "Em serviço";
        break;
      case 'break_start':
        _currentStatus = "Em pausa";
        break;
      case 'break_end':
        _currentStatus = "Em serviço (retorno)";
        break;
      case 'check_out':
        _currentStatus = "Expediente encerrado";
        break;
      default:
        _currentStatus = "Status atualizado";
    }
  }

  Future<void> _registerPunch(
    String type, {
    DateTime? timestamp,
    String? notes,
    String? location,
  }) async {
    if (type == 'check_in' &&
        _todayRecords.any((r) => r['record_type'] == 'check_out')) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Novo Turno'),
          content: const Text(
              'Você já encerrou um turno hoje. Tem certeza que deseja iniciar um novo?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: wineColor),
              child: const Text('Sim, Continuar',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Obter localização atual
      Position? position;
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
        }
      } catch (e) {
        debugPrint('Erro ao obter localização: $e');
      }

      // 2. Criar registro no banco ou na fila offline
      final result = await _apiService.createTimeRecord(
        recordType: type,
        timestamp: timestamp?.toIso8601String(),
        notes: notes,
        location: location,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      await _loadTodayRecords();
      if (result['offline'] == true) {
        _showSuccess(
            'Sem internet. Registro salvo no aparelho para sincronizar depois.');
      } else {
        _showSuccess('Registro de ${_getRecordLabel(type)} salvo com sucesso!');
        unawaited(_trySyncOfflineRecords());
      }
    } catch (e) {
      _showError('Erro ao registrar: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  DateTime? _currentShiftStartDate() {
    final lastCheckInIndex = _todayRecords.lastIndexWhere(
      (record) => record['record_type'] == 'check_in',
    );
    if (lastCheckInIndex < 0) return null;

    return DateTime.parse(_todayRecords[lastCheckInIndex]['timestamp']);
  }

  Future<void> _finishInternShiftAt1930() async {
    final shiftStart = _currentShiftStartDate();
    if (shiftStart == null) {
      _showError('Nao encontrei a entrada deste turno para fechar as 19:30.');
      return;
    }

    final closeAt = DateTime(
      shiftStart.year,
      shiftStart.month,
      shiftStart.day,
      19,
      30,
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fechar ponto as 19:30'),
        content: Text(
          'O expediente sera finalizado em ${DateFormat('dd/MM/yyyy HH:mm:ss').format(closeAt)}, no mesmo dia em que o turno comecou.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: wineColor),
            child:
                const Text('Confirmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _registerPunch(
      'check_out',
      timestamp: closeAt,
      notes: 'Fechamento manual do estagiario para 19:30',
      location: 'App (19:30)',
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: wineColor));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white),
        const SizedBox(width: 8),
        Text(msg)
      ]),
      backgroundColor: Colors.blue.shade800,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _getRecordLabel(String type) {
    switch (type) {
      case 'check_in':
        return 'Entrada';
      case 'check_out':
        return 'Saída';
      case 'break_start':
        return 'Pausa 1 (Início)';
      case 'break_end':
        return 'Pausa 1 (Retorno)';
      case 'entry_3':
        return 'Pausa 2 (Início)';
      case 'exit_3':
        return 'Pausa 2 (Retorno)';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_outlined, color: wineColor),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const UserChatListScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: _isLoading && _todayRecords.isEmpty
          ? const Center(child: CircularProgressIndicator(color: wineColor))
          : RefreshIndicator(
              onRefresh: () async {
                await _trySyncOfflineRecords(showMessage: true);
                await _loadTodayRecords();
              },
              color: wineColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildClockCard(theme, isDark),
                    const SizedBox(height: 16),
                    if (_pendingOfflineRecordsCount > 0) ...[
                      _buildOfflineSyncBanner(theme),
                      const SizedBox(height: 12),
                    ],
                    _buildStatusCard(theme, isDark),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                    const SizedBox(height: 32),
                    _buildHistoryList(theme, isDark),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildOfflineSyncBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_pendingOfflineRecordsCount registro(s) aguardando internet para sincronizar.',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _isSyncingOffline
                ? null
                : () => _trySyncOfflineRecords(showMessage: true),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
  }

  Widget _buildClockCard(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: theme.primaryColor, width: 4)),
      ),
      child: Column(
        children: [
          Text(_currentDate,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.1)),
          const SizedBox(height: 8),
          Text(_currentTime,
              style: TextStyle(
                  color: theme.primaryColor,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          const SizedBox(height: 12),
          _buildUserTag(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildUserTag(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
              radius: 8,
              backgroundColor: theme.primaryColor.withOpacity(0.8),
              child: Text(_displayUserName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 9, color: Colors.white))),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _displayUserName,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, bool isDark) {
    bool isWorking = _currentStatus.contains("serviço") ||
        _currentStatus.contains("retorno");
    Color statusColor = isWorking
        ? Colors.green
        : (_currentStatus.contains("pausa") ? Colors.orange : wineColor);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text(_currentStatus,
                  style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          Text(_lastActionTime,
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    String? breakAction;
    String breakLabel = 'REGISTRAR ENTRADA';
    bool canExit = false;

    if (_todayRecords.isEmpty ||
        _todayRecords.last['record_type'] == 'check_out') {
      breakAction = 'check_in';
      breakLabel = 'REGISTRAR ENTRADA';
      canExit = false;
    } else {
      final last = _todayRecords.last['record_type'];
      canExit = true;

      int lastCheckInIdx =
          _todayRecords.lastIndexWhere((r) => r['record_type'] == 'check_in');
      var currentSessionRecords = _todayRecords.sublist(lastCheckInIdx);

      int breakStarts = currentSessionRecords
          .where((r) =>
              r['record_type'] == 'break_start' ||
              r['record_type'] == 'entry_3')
          .length;
      if (last == 'check_in' || last == 'break_end') {
        if (breakStarts < 2) {
          breakAction = breakStarts == 0 ? 'break_start' : 'entry_3';
          breakLabel = 'INICIAR PAUSA ${breakStarts + 1}';
        } else {
          breakAction = null;
        }
      } else if (last == 'break_start' || last == 'entry_3') {
        breakAction = last == 'break_start' ? 'break_end' : 'exit_3';
        breakLabel = 'RETORNAR DA PAUSA';
        canExit = false;
      }
    }

    return Column(
      children: [
        if (breakAction != null)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => _registerPunch(breakAction!),
              style: ElevatedButton.styleFrom(
                  backgroundColor: wineColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text(breakLabel,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        if (canExit) ...[
          const SizedBox(height: 10),
          _buildFinishShiftButton(),
        ]
      ],
    );
  }

  Widget _buildFinishShiftButton() {
    final buttonStyle = OutlinedButton.styleFrom(
      side: const BorderSide(color: wineColor, width: 1.5),
      foregroundColor: wineColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    if (!_isInternUser) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton(
          onPressed: () => _registerPunch('check_out'),
          style: buttonStyle,
          child: const Text(
            'FINALIZAR EXPEDIENTE',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _registerPunch('check_out'),
              style: buttonStyle.copyWith(
                shape: WidgetStateProperty.all(
                  const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.horizontal(left: Radius.circular(12)),
                  ),
                ),
              ),
              child: const Text(
                'FINALIZAR EXPEDIENTE',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            tooltip: 'Mais opcoes',
            onSelected: (value) {
              if (value == 'intern_1930') {
                _finishInternShiftAt1930();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'intern_1930',
                child: Text('Fechar ponto 19:30:00'),
              ),
            ],
            child: Container(
              width: 48,
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: wineColor, width: 1.5),
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(12)),
              ),
              child: const Icon(Icons.keyboard_arrow_down, color: wineColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('REGISTROS DE HOJE',
            style: TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
        const SizedBox(height: 12),
        if (_todayRecords.isEmpty)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nenhum registro encontrado hoje',
                      style: TextStyle(color: Colors.grey, fontSize: 12)))),
        ..._todayRecords.reversed
            .map((r) => _buildHistoryItem(r, theme, isDark))
            .toList(),
      ],
    );
  }

  Widget _buildHistoryItem(dynamic record, ThemeData theme, bool isDark) {
    final time =
        DateFormat('HH:mm:ss').format(DateTime.parse(record['timestamp']));
    final type = record['record_type'];
    final isOffline = record['offline'] == true;

    IconData icon;
    Color iconColor;
    switch (type) {
      case 'check_in':
        icon = Icons.login;
        iconColor = Colors.green;
        break;
      case 'break_start':
        icon = Icons.coffee;
        iconColor = Colors.orange;
        break;
      case 'break_end':
        icon = Icons.directions_run;
        iconColor = Colors.blue;
        break;
      case 'check_out':
        icon = Icons.logout;
        iconColor = wineColor;
        break;
      default:
        icon = Icons.access_time;
        iconColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color:
                      isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Text(_getRecordLabel(type),
                  style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOffline) ...[
                const Icon(Icons.sync_problem, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
              ],
              Text(time,
                  style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }
}
