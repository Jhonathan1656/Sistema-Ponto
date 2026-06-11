import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import '../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _selectedUser;
  List<dynamic> _users = [];
  List<dynamic> _dailyRecords = [];
  List<dynamic> _weeklyRecords = [];
  double _weeklyTotalHours = 0;
  DateTime _timelineDate = DateTime.now();
  List<int> _hourlyActivity = List.filled(24, 0);
  Timer? _timer;
  DateTime _now = DateTime.now();

  static const Color wineColor = Color(0xFF8B0000);

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() => _now = DateTime.now());
        _fetchDashboardData();
      }
    });
  }

  String _firstName(dynamic value) {
    final fullName = (value ?? '').toString().trim();
    if (fullName.isEmpty) return '';
    return fullName.split(RegExp(r'\s+')).first;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    try {
      final currentUser = await _apiService.getCurrentUser();
      if (currentUser['role'] == 'admin' || currentUser['role'] == 'manager') {
        _users = await _apiService.getUsers();
      } else {
        _users = [currentUser];
      }
      _selectedUser = _users.first;
      await _fetchDashboardData();
    } catch (e) {
      debugPrint('Erro init: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDashboardData() async {
    if (_selectedUser == null) return;
    try {
      final now = DateTime.now();

      final startDay =
          DateTime(_timelineDate.year, _timelineDate.month, _timelineDate.day)
              .toIso8601String();
      final endDay = DateTime(_timelineDate.year, _timelineDate.month,
              _timelineDate.day, 23, 59, 59)
          .toIso8601String();

      final startToday =
          DateTime(now.year, now.month, now.day).toIso8601String();
      final endToday =
          DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

      final todayData = await _apiService.exportTimesheet(
          startDate: startToday,
          endDate: endToday,
          userId: _selectedUser!['id']);
      final startWeek = now.subtract(Duration(days: now.weekday - 1));
      final startWeekStr =
          DateTime(startWeek.year, startWeek.month, startWeek.day)
              .toIso8601String();
      final weekData = await _apiService.exportTimesheet(
          startDate: startWeekStr,
          endDate: endToday,
          userId: _selectedUser!['id']);

      final rawRecords = await _apiService.getTimeRecords(
          startDate: startDay, endDate: endDay, userId: _selectedUser!['id']);

      setState(() {
        _dailyRecords = todayData['daily_records'];
        _weeklyRecords = weekData['daily_records'];
        _weeklyTotalHours =
            double.tryParse(weekData['summary']['total_hours']) ?? 0.0;
        _calculateHourlyActivityDetail(rawRecords);
      });
    } catch (e) {
      debugPrint('Erro dashboard: $e');
    }
  }

  void _calculateHourlyActivityDetail(List<dynamic> rawRecords) {
    _hourlyActivity = List.filled(24, 0);
    final now = DateTime.now();
    bool isToday = _timelineDate.year == now.year &&
        _timelineDate.month == now.month &&
        _timelineDate.day == now.day;

    rawRecords.sort((a, b) =>
        (a['timestamp'] as String).compareTo(b['timestamp'] as String));

    DateTime? lastEntry;
    DateTime? lastBreakStart;

    for (var r in rawRecords) {
      final DateTime ts = DateTime.parse(r['timestamp']);
      final int h = ts.hour;
      if (h >= 24) continue;

      String type = r['record_type'];

      if (type == 'check_in' || type == 'break_end' || type == 'entry_3') {
        lastEntry = ts;
        if (lastBreakStart != null) {
          for (int i = lastBreakStart.hour; i < h; i++) {
            if (i < 24) _hourlyActivity[i] = 2;
          }
          lastBreakStart = null;
        }
      } else if (type == 'break_start' ||
          type == 'exit_3' ||
          type == 'check_out') {
        if (lastEntry != null) {
          for (int i = lastEntry.hour; i < h; i++) {
            if (i < 24) _hourlyActivity[i] = 1;
          }
          if (type != 'check_out') lastBreakStart = ts;
          lastEntry = null;
        }
      }
    }

    if (isToday) {
      if (lastEntry != null) {
        for (int i = lastEntry.hour; i <= now.hour; i++) {
          if (i < 24) _hourlyActivity[i] = 1;
        }
      } else if (lastBreakStart != null) {
        for (int i = lastBreakStart.hour; i <= now.hour; i++) {
          if (i < 24) _hourlyActivity[i] = 2;
        }
      }
      if (now.hour < 24) _hourlyActivity[now.hour] = 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: wineColor))
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              color: wineColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, topInset + 32, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildUserSwitcher(),
                    const SizedBox(height: 24),
                    _buildSummaryCards(),
                    const SizedBox(height: 24),
                    _buildTimelineChart(),
                    const SizedBox(height: 24),
                    _buildWeeklyTimelineChart(),
                    const SizedBox(height: 24),
                    _buildWeeklyHours(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CONTROLE DE JORNADA',
                  style: TextStyle(
                      color: Colors.grey, fontSize: 10, letterSpacing: 1.2)),
              Text(
                _firstName(_selectedUser?['name']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(DateFormat('EEE, dd MMM yyyy', 'pt_BR').format(_now),
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Text(DateFormat('HH:mm:ss').format(_now),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: textColor)),
          ],
        ),
      ],
    );
  }

  Widget _buildUserSwitcher() {
    if (_users.length <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<dynamic>(
        value: _selectedUser?['id'],
        dropdownColor: Theme.of(context).cardColor,
        decoration: InputDecoration(
          labelText: 'Selecionar Funcionário',
          labelStyle: const TextStyle(color: Colors.grey),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: wineColor),
          ),
          filled: true,
          fillColor: Theme.of(context).cardColor,
        ),
        style: TextStyle(
            color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 14),
        items: _users.map((user) {
          return DropdownMenuItem(
            value: user['id'],
            child: Text(user['name']),
          );
        }).toList(),
        onChanged: (val) {
          if (val != null) {
            final user = _users.firstWhere((u) => u['id'] == val);
            setState(() => _selectedUser = user);
            _fetchDashboardData();
          }
        },
      ),
    );
  }

  Widget _buildSummaryCards() {
    final record = _dailyRecords.isNotEmpty ? _dailyRecords.first : null;
    final double hours = record?['total_hours'] ?? 0.0;
    final int h = hours.toInt();
    final int m = ((hours - h) * 60).round();

    bool isEstagiario = (_selectedUser?['role'] ?? '')
            .toString()
            .toLowerCase()
            .contains('estag') ||
        (_selectedUser?['role'] ?? '')
            .toString()
            .toLowerCase()
            .contains('intern');

    final double weeklyGoal = isEstagiario ? 30.0 : 44.0;
    final double balance = _weeklyTotalHours - weeklyGoal;
    final String balanceStr = balance >= 0
        ? '+${balance.toStringAsFixed(1)}h'
        : '${balance.toStringAsFixed(1)}h';

    return Row(
      children: [
        _buildCard('HORAS HOJE', '${h}h ${m}m', 'acumulado', isPrimary: true),
        const SizedBox(width: 10),
        _buildCard('ENTRADA', record?['check_in'] ?? '--:--', 'no prazo'),
        const SizedBox(width: 10),
        _buildCard('SALDO SEMANA', balanceStr,
            balance >= 0 ? 'acima da meta' : 'abaixo da meta'),
      ],
    );
  }

  Widget _buildCard(String title, String value, String sub,
      {bool isPrimary = false}) {
    final cardColor =
        isPrimary ? wineColor.withOpacity(0.1) : Theme.of(context).cardColor;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isPrimary ? wineColor : Colors.white.withOpacity(0.05),
              width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(
                    color: isPrimary ? wineColor : Colors.grey, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('LINHA DO TEMPO — DIA',
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _timelineDate,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _timelineDate = picked);
                    _fetchDashboardData();
                  }
                },
                icon: const Icon(Icons.calendar_today,
                    size: 12, color: wineColor),
                label: Text(
                  DateFormat('dd/MM/yy').format(_timelineDate),
                  style: const TextStyle(
                      color: wineColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: Size.zero),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: BarChart(
              BarChartData(
                maxY: 10,
                barGroups: List.generate(24, (i) {
                  int type = _hourlyActivity[i];
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: type > 0 ? 8 : 0,
                        color: type == 2
                            ? Colors.orange
                            : (type == 3
                                ? Colors.blue
                                : Colors.blue.withOpacity(0.4)),
                        width: 6,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ],
                  );
                }),
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 18,
                      getTitlesWidget: (val, meta) {
                        if (val % 2 == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('${val.toInt()}h',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 8)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildLegend(Colors.blue.withOpacity(0.4), 'Trabalhado'),
              const SizedBox(width: 12),
              _buildLegend(Colors.orange, 'Pausa'),
              const SizedBox(width: 12),
              _buildLegend(Colors.blue, 'Momento atual'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 9)),
      ],
    );
  }

  Widget _buildWeeklyTimelineChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LINHA DO TEMPO — SEMANA',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SizedBox(
            height: 100,
            child: BarChart(
              BarChartData(
                maxY: 12,
                barGroups: List.generate(7, (index) {
                  DateTime date = DateTime.now().subtract(
                      Duration(days: DateTime.now().weekday - 1 - index));
                  String dateKey = DateFormat('yyyy-MM-dd').format(date);

                  final Map<String, dynamic>? record =
                      _weeklyRecords.cast<Map<String, dynamic>?>().firstWhere(
                            (r) => r?['date'] == dateKey,
                            orElse: () => null,
                          );

                  double grossHours = 0;
                  if (record != null &&
                      record['check_in'] != null &&
                      record['check_out'] != null) {
                    int startH = int.parse(record['check_in'].split(':')[0]);
                    int endH = int.parse(record['check_out'].split(':')[0]);
                    grossHours = (endH - startH).toDouble();
                  }

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: grossHours > 0 ? grossHours : 0.1,
                        color: wineColor.withOpacity(0.8),
                        width: 10,
                        borderRadius: BorderRadius.circular(2),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: 10,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withOpacity(0.03)
                              : Colors.black.withOpacity(0.03),
                        ),
                      ),
                    ],
                    showingTooltipIndicators: [0],
                  );
                }),
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 18,
                      getTitlesWidget: (val, meta) {
                        const days = [
                          'Seg',
                          'Ter',
                          'Qua',
                          'Qui',
                          'Sex',
                          'Sáb',
                          'Dom'
                        ];
                        if (val >= 0 && val < 7) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(days[val.toInt()],
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 8)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: false,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.transparent,
                    tooltipPadding: EdgeInsets.zero,
                    tooltipMargin: 4,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        rod.toY > 0.1 ? '${rod.toY.toInt()}h' : '',
                        TextStyle(
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 9),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyHours() {
    bool isEstagiario = (_selectedUser?['role'] ?? '')
            .toString()
            .toLowerCase()
            .contains('estag') ||
        (_selectedUser?['role'] ?? '')
            .toString()
            .toLowerCase()
            .contains('intern');

    final double weeklyGoal = isEstagiario ? 30.0 : 44.0;
    final double progress = (_weeklyTotalHours / weeklyGoal).clamp(0.0, 1.0);
    final int h = _weeklyTotalHours.toInt();
    final int m = ((_weeklyTotalHours - h) * 60).round();
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HORAS NA SEMANA (${isEstagiario ? "META 30H" : "META 44H"})',
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.03)
                          : Colors.black.withOpacity(0.03),
                  color: wineColor,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${h}h ${m}m',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textColor)),
                  Row(
                    children: [
                      Text('meta: ${weeklyGoal.toInt()}h',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 10)),
                      const SizedBox(width: 8),
                      if (progress < 0.8)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20)),
                          child: const Text('ATENÇÃO',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
