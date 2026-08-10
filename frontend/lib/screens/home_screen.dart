import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/user_notification_bell.dart';

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
  bool _punchInFlight = false;
  int _pendingOfflineRecordsCount = 0;
  DateTime? _lastOfflineSyncAttempt;
  String? _lastInternReminderDate;
  // Entrada de um turno que comecou em um dia anterior e nunca foi fechado
  // (estagiario esqueceu de bater a saida e o dia virou). Null quando nao ha.
  DateTime? _carriedOpenShiftStart;
  Map<String, dynamic> _effectiveSchedule = const {
    'shift_start': '13:30',
    'shift_end': '19:30',
    'start_allowed_from': '13:25',
    'start_allowed_until': '19:25',
    'overtime_prompt_after': '19:35',
    'timezone': 'America/Sao_Paulo',
  };
  Map<String, dynamic>? _scheduleState;
  DateTime? _lastScheduleRefresh;
  bool _refreshingSchedule = false;

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
              now.difference(_lastOfflineSyncAttempt!).inSeconds >= 60)) {
        _lastOfflineSyncAttempt = now;
        unawaited(_trySyncOfflineRecords());
      }
      // Refresh de fundo espacado (90s): cada refresh le pontos do Firestore.
      // A meta de 30s deixava as leituras muito altas para a cota gratuita.
      // Bater ponto ja recarrega na hora; o pull-to-refresh tambem.
      if (_isInternUser &&
          !_refreshingSchedule &&
          (_lastScheduleRefresh == null ||
              now.difference(_lastScheduleRefresh!).inSeconds >= 90)) {
        _lastScheduleRefresh = now;
        unawaited(_refreshWorkSchedule(refreshRecords: true));
      }
    }
  }

  void _checkAutoActions(DateTime now) {
    // 1. Fechamento automatico de pausa apos 3h aberta.
    if (_todayRecords.isNotEmpty && !_isAutoClosingBreak) {
      final last = _todayRecords.last;
      if (last['record_type'] == 'break_start' ||
          last['record_type'] == 'entry_3') {
        final startTime = DateTime.parse(last['timestamp']);
        final diff = now.difference(startTime).inMinutes;

        if (diff >= 180) {
          _autoCloseBreak(last['record_type'], startTime);
        }
      }
    }

    // 2. Aviso no limite configurado para o estagiario.
    bool isEstagiario = _isInternUser;

    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final reminder = _dateAtConfiguredTime(now, 'overtime_prompt_after');
    if (isEstagiario &&
        _hasOpenPoint &&
        !now.isBefore(reminder) &&
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
        notes: "Retorno automatico (pausa excedeu 3h; ajustado para 1h)",
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
                'Sua pausa excedeu 3h e foi fechada automaticamente com 1 hora de pausa.'),
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
    if (_carriedOpenShiftStart != null) return true;
    if (_todayRecords.isEmpty) return false;
    final last = _todayRecords.last['record_type']?.toString();
    return last != null && last != 'check_out';
  }

  DateTime _dateAtConfiguredTime(DateTime day, String field) {
    final parts = (_effectiveSchedule[field] ?? '').toString().split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  String? get _overtimeRequestStatus {
    final request = _scheduleState?['overtime_request'];
    if (request is Map) return request['status']?.toString();
    return null;
  }

  bool get _isOvertimeDecisionRequired {
    if (!_isInternUser || !_hasOpenPoint) return false;
    if (_overtimeRequestStatus == 'approved') return false;
    final shiftStart = _currentShiftStartDate();
    if (shiftStart == null) return false;
    final threshold =
        _dateAtConfiguredTime(shiftStart, 'overtime_prompt_after');
    return !DateTime.now().isBefore(threshold);
  }

  Future<void> _configureInternReminder() async {
    if (!_isInternUser || !_hasOpenPoint) {
      await NotificationService.cancelInternOpenPointReminder();
      return;
    }

    final now = DateTime.now();
    await NotificationService.scheduleInternOpenPointReminder(
      now,
      scheduledAt: _dateAtConfiguredTime(now, 'overtime_prompt_after'),
    );
  }

  Future<void> _notifyInternIfPointIsOpen() async {
    await _loadTodayRecords();
    if (!_isInternUser || !_hasOpenPoint) return;

    await NotificationService.showInternOpenPointReminder();
  }

  String get _displayUserName {
    final name = (_user?['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final email = (_user?['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;

    return 'Carregando...';
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _apiService.getCurrentUser();
      _user = user;
      await _refreshWorkSchedule();
      await _trySyncOfflineRecords();
      await _loadTodayRecords();
    } catch (e) {
      debugPrint('Erro init: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshWorkSchedule({bool refreshRecords = false}) async {
    if (!_isInternUser || _refreshingSchedule) return;
    _refreshingSchedule = true;
    try {
      final state = await _apiService.getEffectiveWorkSchedule();
      final schedule = state['schedule'];
      if (mounted && schedule is Map) {
        setState(() {
          _scheduleState = state;
          _effectiveSchedule = Map<String, dynamic>.from(schedule);
        });
      }
      if (refreshRecords) await _loadTodayRecords();
    } catch (e) {
      debugPrint('Horario efetivo indisponivel: $e');
    } finally {
      _refreshingSchedule = false;
    }
  }

  Future<void> _loadTodayRecords() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toIso8601String();
      final end =
          DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

      // Estagiario precisa da janela de 14 dias (turno que atravessou o dia),
      // e ela ja contem o dia de hoje: uma consulta so serve as duas coisas.
      // Antes eram duas leituras do Firestore a cada atualizacao da tela.
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final windowStart = _isInternUser
          ? todayMidnight.subtract(const Duration(days: 14)).toIso8601String()
          : start;
      final windowRecords =
          await _apiService.getTimeRecords(startDate: windowStart, endDate: end);
      final records = windowRecords.where((item) {
        final timestamp = (item as Map)['timestamp'].toString();
        return timestamp.compareTo(start) >= 0;
      }).toList();
      final pendingRecords = await _apiService.getOfflineRecords();

      _refreshCarriedOpenShift(now, windowRecords);

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

  // Procura, alem do dia de hoje, um turno que ficou aberto em um dia anterior
  // (check_in sem check_out). Isso garante que a tela reconheca o turno mesmo
  // depois da virada do dia, oferecendo a decisao (continuar ou fechar as 19:30)
  // em vez de travar com "Ja existe um turno aberto".
  // A janela de 14 dias e a MESMA que o backend usa para decidir se ha turno
  // aberto. Com 10 dias aqui, um check_in preso entre 10 e 14 dias atras ficava
  // invisivel na tela (que so mostra hoje) enquanto o backend recusava a
  // entrada com "Ja existe um turno aberto". Recebe os registros ja lidos por
  // _loadTodayRecords em vez de consultar o Firestore de novo.
  void _refreshCarriedOpenShift(DateTime now, List<dynamic> windowRecords) {
    if (!_isInternUser) {
      _carriedOpenShiftStart = null;
      return;
    }
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final ordered = windowRecords
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList()
      ..sort((a, b) =>
          a['timestamp'].toString().compareTo(b['timestamp'].toString()));

    DateTime? openStart;
    for (final record in ordered) {
      final type = record['record_type']?.toString();
      if (type == 'check_in') {
        openStart = DateTime.tryParse(record['timestamp']?.toString() ?? '');
      } else if (type == 'check_out') {
        openStart = null;
      }
    }

    _carriedOpenShiftStart =
        (openStart != null && openStart.isBefore(todayMidnight))
            ? openStart
            : null;
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
        DateFormat('HH:mm:ss').format(DateTime.parse(last['timestamp']).toLocal());
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
    // Trava de reentrada: evita duplo-registro por toque duplo no botao.
    if (_punchInFlight) return;
    setState(() => _punchInFlight = true);

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
      if (confirm != true) {
        setState(() => _punchInFlight = false);
        return;
      }
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

      // 2. Estagiarios usam validacao autoritativa do backend na entrada/saida.
      final attemptedAt = timestamp ?? DateTime.now();
      final Map<String, dynamic> result;
      if (_isInternUser && (type == 'check_in' || type == 'check_out')) {
        result = await _apiService.createScheduleControlledPunch(
          recordType: type,
          timestamp: attemptedAt.toIso8601String(),
          notes: notes,
          location: location,
          latitude: position?.latitude,
          longitude: position?.longitude,
        );
        if (result['status'] == 'approval_required') {
          await _offerScheduleApproval(
            result['request_type']?.toString() ?? 'start_exception',
            attemptedAt,
            position,
            reason: result['reason']?.toString(),
          );
          return;
        }
      } else {
        result = await _apiService.createTimeRecord(
          recordType: type,
          timestamp: timestamp?.toIso8601String(),
          notes: notes,
          location: location,
          latitude: position?.latitude,
          longitude: position?.longitude,
        );
      }

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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _punchInFlight = false;
        });
      }
    }
  }

  Future<void> _offerScheduleApproval(
    String requestType,
    DateTime attemptedAt,
    Position? position, {
    String? reason,
  }) async {
    if (!mounted) return;
    final isStart = requestType == 'start_exception';
    final formKey = GlobalKey<FormState>();
    final observationController = TextEditingController();
    final observation = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isStart ? 'Entrada fora do horario' : 'Horario encerrado'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isStart
                      ? reason == 'non_working_day'
                          ? 'Estagiarios trabalham de segunda a sexta. Para iniciar no fim de semana, peca liberacao e explique o que voce vai fazer.'
                          : 'Seu horario permitido para iniciar e de ${_effectiveSchedule['start_allowed_from']} ate ${_effectiveSchedule['start_allowed_until']}. Para pedir liberacao, explique o motivo.'
                      : 'Para continuar depois de ${_effectiveSchedule['shift_end']}, explique ao gestor o que voce esta fazendo.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observationController,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Observacao para o gestor',
                    hintText:
                        'Ex.: Estou finalizando o relatorio do projeto...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Explique o motivo da solicitacao.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('SAIR'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, observationController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: wineColor),
            child: const Text('SOLICITAR LIBERACAO',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    observationController.dispose();
    if (observation == null) return;

    try {
      final response = await _apiService.createScheduleApprovalRequest(
        requestType: requestType,
        attemptedAt: attemptedAt.toIso8601String(),
        shiftStartAt: _currentShiftStartDate()?.toIso8601String(),
        location: 'App',
        notes: observation,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      await _refreshWorkSchedule();
      final existing = response['status'] == 'existing';
      _showSuccess(existing
          ? 'Sua solicitacao ja esta aguardando um gestor.'
          : 'Solicitacao enviada para os gestores.');
    } catch (e) {
      _showError('Nao foi possivel solicitar a liberacao: $e');
    }
  }

  DateTime? _currentShiftStartDate() {
    final lastCheckInIndex = _todayRecords.lastIndexWhere(
      (record) => record['record_type'] == 'check_in',
    );
    if (lastCheckInIndex >= 0) {
      return DateTime.parse(_todayRecords[lastCheckInIndex]['timestamp']).toLocal();
    }
    // Turno que comecou em um dia anterior e nunca foi fechado.
    return _carriedOpenShiftStart;
  }

  Future<void> _finishInternShiftAtScheduledEnd() async {
    final shiftStart = _currentShiftStartDate();
    if (shiftStart == null) {
      _showError('Nao encontrei a entrada deste turno para fechar no horario.');
      return;
    }

    final closeAt = _dateAtConfiguredTime(shiftStart, 'shift_end');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Fechar ponto as ${_effectiveSchedule['shift_end']}'),
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

    setState(() => _isLoading = true);
    try {
      await _apiService.createScheduleControlledPunch(
        recordType: 'check_out',
        timestamp: closeAt.toIso8601String(),
        notes: 'Fechamento no horario configurado do estagiario',
        location: 'App (horario programado)',
        closeAtScheduledEnd: true,
      );
      await _loadTodayRecords();
      await _refreshWorkSchedule();
      _showSuccess('Ponto fechado em ${_effectiveSchedule['shift_end']}.');
    } catch (e) {
      _showError('Erro ao fechar o ponto: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          const UserNotificationBell(),
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
          : _isOvertimeDecisionRequired
              ? _buildOvertimeDecisionScreen(theme)
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

  Widget _buildOvertimeDecisionScreen(ThemeData theme) {
    final pending = _overtimeRequestStatus == 'pending';
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey.shade400,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _refreshWorkSchedule(refreshRecords: true);
          },
          color: wineColor,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 70, 20, 24),
            children: [
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.schedule_outlined,
                          size: 58, color: wineColor),
                      const SizedBox(height: 16),
                      const Text(
                        'HORARIO PROGRAMADO ENCERRADO',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _carriedOpenShiftStart != null
                            ? 'Voce iniciou um turno em ${DateFormat('dd/MM/yyyy \'as\' HH:mm').format(_carriedOpenShiftStart!)} e nao registrou a saida. O dia ja virou: escolha continuar (com liberacao do gestor) ou fechar o ponto as ${_effectiveSchedule['shift_end']} do dia em que comecou.'
                            : 'Seu expediente terminou as ${_effectiveSchedule['shift_end']}. Para continuar trabalhando, a gestao precisa liberar o horario.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                            height: 1.4),
                      ),
                      if (pending) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.hourglass_top, color: Colors.orange),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Solicitacao enviada. Aguardando um gestor.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: pending
                              ? null
                              : () => _offerScheduleApproval(
                                    'overtime',
                                    DateTime.now(),
                                    null,
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: wineColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.send_outlined),
                          label: Text(pending
                              ? 'AGUARDANDO LIBERACAO'
                              : 'CONTINUAR E NOTIFICAR GESTOR'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _finishInternShiftAtScheduledEnd,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: wineColor,
                            side: const BorderSide(color: wineColor),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.logout),
                          label: Text(
                              'FECHAR PONTO AS ${_effectiveSchedule['shift_end']}'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscardOffline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar pendências?'),
        content: Text(
            'Isso apaga os $_pendingOfflineRecordsCount registro(s) que ainda '
            'não sincronizaram. Use apenas se eles estiverem presos ou forem '
            'inválidos — os pontos descartados não serão enviados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Descartar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _apiService.clearOfflineRecords();
    if (!mounted) return;
    setState(() => _pendingOfflineRecordsCount = 0);
    _showSuccess('Pendências offline descartadas.');
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
          IconButton(
            onPressed: _isSyncingOffline ? null : _confirmDiscardOffline,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: Colors.orange,
            tooltip: 'Descartar pendências',
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
              onPressed:
                  _punchInFlight ? null : () => _registerPunch(breakAction!),
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
          onPressed:
              _punchInFlight ? null : () => _registerPunch('check_out'),
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
              onPressed:
              _punchInFlight ? null : () => _registerPunch('check_out'),
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
                _finishInternShiftAtScheduledEnd();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'intern_1930',
                child: Text('Fechar no horario programado'),
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
        DateFormat('HH:mm:ss').format(DateTime.parse(record['timestamp']).toLocal());
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
