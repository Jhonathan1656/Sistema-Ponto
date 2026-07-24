import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

/// Paleta de series validada para as superficies do app (card branco no claro,
/// #1E1E1E no escuro). Os passos do modo escuro sao proprios, nao um inverso
/// automatico do claro.
class _VizPalette {
  const _VizPalette(this.isDark);
  final bool isDark;

  Color get normal => isDark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);
  Color get extra50 => isDark ? const Color(0xFFD95926) : const Color(0xFFEB6834);
  Color get extra100 =>
      isDark ? const Color(0xFF199E70) : const Color(0xFF1BAF7A);

  Color get grid => isDark ? const Color(0xFF2C2C2A) : const Color(0xFFE1E0D9);
  Color get muted => const Color(0xFF898781);
  Color get surface => isDark ? const Color(0xFF1E1E1E) : Colors.white;
}

class MonthlyDashboardScreen extends StatefulWidget {
  const MonthlyDashboardScreen({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<MonthlyDashboardScreen> createState() => _MonthlyDashboardScreenState();
}

class _MonthlyDashboardScreenState extends State<MonthlyDashboardScreen> {
  static const Color wineColor = Color(0xFF8B0000);

  final _apiService = ApiService();
  bool _isLoading = true;
  String? _error;

  late DateTime _month;
  List<Map<String, dynamic>> _days = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // O periodo fecha no dia 28. A partir do dia 29 ja estamos no periodo
    // do mes seguinte.
    _month = now.day >= 29
        ? DateTime(now.year, now.month + 1)
        : DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final start = _periodStart;
      final end = DateTime(
          _periodEnd.year, _periodEnd.month, _periodEnd.day, 23, 59, 59);
      final data = await _apiService.exportTimesheet(
        startDate: start.toIso8601String(),
        endDate: end.toIso8601String(),
        userId: widget.user['id'],
      );
      if (!mounted) return;
      setState(() {
        _days = (data['daily_records'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _summary = Map<String, dynamic>.from(data['summary'] as Map);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  // --- DERIVADOS ---

  /// Periodo da folha: 29 do mes anterior ate 28 do mes de referencia.
  /// O construtor do DateTime normaliza casos como "29 de fevereiro".
  DateTime get _periodStart => DateTime(_month.year, _month.month - 1, 29);
  DateTime get _periodEnd => DateTime(_month.year, _month.month, 28);
  int get _periodDays => _periodEnd.difference(_periodStart).inDays + 1;
  DateTime _dateAt(int index) => _periodStart.add(Duration(days: index));

  /// Meta do periodo = carga diaria x dias/semana x 4 semanas.
  /// Estagiario trabalha 5 dias/semana; demais cargos, 6.
  double get _target {
    final daily =
        double.tryParse('${widget.user['daily_hours'] ?? 8}') ?? 8.0;
    final role = '${widget.user['role'] ?? ''}'.toLowerCase();
    final isIntern = role.contains('intern') || role.contains('estag');
    final daysPerWeek = isIntern ? 5 : 6;
    return daily * daysPerWeek * 4;
  }

  double _num(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

  double get _total => double.tryParse('${_summary['total_hours'] ?? 0}') ?? 0;
  double get _regular =>
      double.tryParse('${_summary['total_regular_hours'] ?? 0}') ?? 0;
  double get _e50 => double.tryParse('${_summary['total_50'] ?? 0}') ?? 0;
  double get _e100 => double.tryParse('${_summary['total_100'] ?? 0}') ?? 0;
  double get _extras =>
      (double.tryParse('${_summary['total_extras'] ?? 0}') ?? 0) + _e50 + _e100;

  List<Map<String, dynamic>> get _worked =>
      _days.where((d) => _num(d['total_hours']) > 0).toList();

  double get _avgPerDay =>
      _worked.isEmpty ? 0 : _total / _worked.length;

  /// Media do horario de entrada, em minutos desde a meia-noite.
  int? get _avgCheckIn {
    final mins = <int>[];
    for (final d in _days) {
      final raw = d['check_in'];
      if (raw is! String || !raw.contains(':')) continue;
      final parts = raw.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) continue;
      mins.add(h * 60 + m);
    }
    if (mins.isEmpty) return null;
    return (mins.reduce((a, b) => a + b) / mins.length).round();
  }

  Map<String, dynamic>? get _bestDay {
    if (_worked.isEmpty) return null;
    return _worked.reduce(
        (a, b) => _num(a['total_hours']) >= _num(b['total_hours']) ? a : b);
  }

  Map<String, dynamic>? _recordForDate(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    for (final d in _days) {
      if (d['date'] == key) return d;
    }
    return null;
  }

  String _hm(double hours) {
    final total = (hours * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viz = _VizPalette(isDark);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: wineColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Meu Mês', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: wineColor))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: wineColor,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMonthSwitcher(),
                        const SizedBox(height: 16),
                        _buildHero(viz),
                        const SizedBox(height: 16),
                        _buildStatGrid(),
                        const SizedBox(height: 16),
                        _buildDailyChart(viz),
                        const SizedBox(height: 16),
                        _buildComposition(viz),
                        const SizedBox(height: 16),
                        _buildRhythm(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Não foi possível carregar o mês',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: child,
    );
  }

  Widget _buildMonthSwitcher() {
    final label = DateFormat('MMMM yyyy', 'pt_BR').format(_month);
    final now = DateTime.now();
    // Periodo atual: a partir do dia 29 ja conta o mes seguinte.
    final currentPeriod = now.day >= 29
        ? DateTime(now.year, now.month + 1)
        : DateTime(now.year, now.month);
    final isFuture = !_month.isBefore(currentPeriod);
    final range =
        '${DateFormat('dd/MM').format(_periodStart)} – ${DateFormat('dd/MM').format(_periodEnd)}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () => _shiftMonth(-1),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Período anterior',
        ),
        Column(
          children: [
            Text(
              '${label[0].toUpperCase()}${label.substring(1)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(range,
                style: const TextStyle(fontSize: 11, color: Color(0xFF898781))),
          ],
        ),
        IconButton(
          onPressed: isFuture ? null : () => _shiftMonth(1),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Próximo período',
        ),
      ],
    );
  }

  /// Numero-heroi: o total do mes e a distancia ate a meta.
  Widget _buildHero(_VizPalette viz) {
    final target = _target;
    final pct = target <= 0 ? 0.0 : (_total / target).clamp(0.0, 1.0);
    final delta = _total - target;
    final ahead = delta >= 0;

    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HORAS NO MÊS',
              style: TextStyle(
                  color: viz.muted,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_total.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 44, fontWeight: FontWeight.bold, height: 1)),
              const SizedBox(width: 4),
              Text('h', style: TextStyle(fontSize: 18, color: viz.muted)),
              const Spacer(),
              Text('meta ${target.toStringAsFixed(0)}h',
                  style: TextStyle(color: viz.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: viz.grid,
              valueColor: AlwaysStoppedAnimation<Color>(viz.normal),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(ahead ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: ahead ? const Color(0xFF0CA30C) : const Color(0xFFD03B3B)),
              const SizedBox(width: 6),
              Text(
                ahead
                    ? '${_hm(delta.abs())} acima da meta'
                    : '${_hm(delta.abs())} abaixo da meta',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ahead
                        ? const Color(0xFF0CA30C)
                        : const Color(0xFFD03B3B)),
              ),
              const Spacer(),
              Text('${(pct * 100).toStringAsFixed(0)}% da meta',
                  style: TextStyle(color: viz.muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    final avg = _avgCheckIn;
    final entrada = avg == null
        ? '--:--'
        : '${(avg ~/ 60).toString().padLeft(2, '0')}:${(avg % 60).toString().padLeft(2, '0')}';

    final tiles = [
      _StatTile('DIAS TRABALHADOS', '${_worked.length}',
          'de $_periodDays dias'),
      _StatTile('MÉDIA POR DIA', _hm(_avgPerDay), 'nos dias com registro'),
      _StatTile('HORAS EXTRAS', _hm(_extras), '50% + 100%'),
      _StatTile('ENTRADA MÉDIA', entrada, 'horário típico'),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final twoCols = c.maxWidth < 560;
        final w = twoCols ? (c.maxWidth - 12) / 2 : (c.maxWidth - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: tiles
              .map((t) => SizedBox(width: w, child: _buildTile(t)))
              .toList(),
        );
      },
    );
  }

  Widget _buildTile(_StatTile t) {
    return _card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFF898781),
                  fontSize: 9,
                  letterSpacing: 1,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(t.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(t.hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF898781), fontSize: 10)),
        ],
      ),
    );
  }

  /// Barras empilhadas: uma por dia do mes, decompostas em normal / 50 / 100.
  Widget _buildDailyChart(_VizPalette viz) {
    var maxY = 0.0;
    for (var i = 0; i < _periodDays; i++) {
      final rec = _recordForDate(_dateAt(i));
      if (rec != null) {
        final t = _num(rec['total_hours']);
        if (t > maxY) maxY = t;
      }
    }
    maxY = (maxY < 8 ? 8 : maxY + 2).ceilToDouble();

    // Vao de 2px entre segmentos, convertido de pixels para unidades do eixo.
    const chartHeight = 180.0;
    final gap = maxY * (2 / chartHeight);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HORAS POR DIA',
              style: TextStyle(
                  color: viz.muted,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Toque numa barra para ver o detalhe do dia',
              style: TextStyle(color: viz.muted, fontSize: 11)),
          const SizedBox(height: 20),
          SizedBox(
            height: chartHeight,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceBetween,
                barGroups: List.generate(_periodDays, (i) {
                  final rec = _recordForDate(_dateAt(i));
                  final normal = rec == null ? 0.0 : _num(rec['regular_hours']);
                  final x50 = rec == null ? 0.0 : _num(rec['extra_50']);
                  final x100 = rec == null ? 0.0 : _num(rec['extra_100']);
                  final total = normal + x50 + x100;

                  final stack = <BarChartRodStackItem>[];
                  var cursor = 0.0;
                  void push(double value, Color color) {
                    if (value <= 0) return;
                    final from = cursor == 0 ? 0.0 : cursor + gap;
                    final to = cursor + value;
                    if (to > from) {
                      stack.add(BarChartRodStackItem(from, to, color));
                    }
                    cursor = to;
                  }

                  push(normal, viz.normal);
                  push(x50, viz.extra50);
                  push(x100, viz.extra100);

                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: total > 0 ? total : 0,
                        rodStackItems: stack,
                        color: Colors.transparent,
                        width: 6,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: viz.grid, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: maxY / 4,
                      getTitlesWidget: (v, meta) => Text(
                        '${v.toInt()}h',
                        style: TextStyle(color: viz.muted, fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= _periodDays) {
                          return const SizedBox.shrink();
                        }
                        final day = _dateAt(i).day;
                        // Rotula o inicio do periodo, viradas de mes e multiplos de 5.
                        if (i != 0 && day != 1 && day % 5 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('$day',
                              style: TextStyle(color: viz.muted, fontSize: 9)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: viz.isDark
                        ? const Color(0xFF2C2C2A)
                        : const Color(0xFF0B0B0B),
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, gi, rod, ri) {
                      final date = _dateAt(group.x);
                      final dayLabel = DateFormat('dd/MM').format(date);
                      final rec = _recordForDate(date);
                      if (rec == null || rod.toY <= 0) {
                        return BarTooltipItem(
                          '$dayLabel\nsem registro',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        );
                      }
                      final n = _num(rec['regular_hours']);
                      final a = _num(rec['extra_50']);
                      final b = _num(rec['extra_100']);
                      final buf = StringBuffer('$dayLabel · ${_hm(rod.toY)}');
                      buf.write('\nNormal ${_hm(n)}');
                      if (a > 0) buf.write('\nExtra 50% ${_hm(a)}');
                      if (b > 0) buf.write('\nExtra 100% ${_hm(b)}');
                      return BarTooltipItem(
                        buf.toString(),
                        const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            height: 1.4,
                            fontWeight: FontWeight.w500),
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

  /// Legenda + valores. Os numeros diretos sao o "relief" exigido pelo
  /// contraste do verde sobre o card claro — a cor nunca informa sozinha.
  Widget _buildComposition(_VizPalette viz) {
    final rows = [
      ('Normal', _regular, viz.normal),
      ('Extra 50%', _e50, viz.extra50),
      ('Extra 100%', _e100, viz.extra100),
    ];
    final sum = rows.fold<double>(0, (p, r) => p + r.$2);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('COMPOSIÇÃO DAS HORAS',
              style: TextStyle(
                  color: viz.muted,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...rows.map((r) {
            final pct = sum <= 0 ? 0.0 : r.$2 / sum;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: r.$3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 82,
                    child: Text(r.$1,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: viz.grid,
                        valueColor: AlwaysStoppedAnimation<Color>(r.$3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 62,
                    child: Text(_hm(r.$2),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRhythm() {
    final best = _bestDay;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DESTAQUES',
              style: TextStyle(
                  color: Color(0xFF898781),
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (best != null)
            _highlight(
              Icons.local_fire_department,
              'Dia mais longo',
              '${DateFormat('dd/MM').format(DateTime.parse(best['date']))} · ${_hm(_num(best['total_hours']))}',
            ),
          _highlight(
            Icons.event_available,
            'Dias com registro',
            '${_worked.length} de $_periodDays',
          ),
          _highlight(
            Icons.speed,
            'Ritmo médio',
            '${_hm(_avgPerDay)} por dia trabalhado',
          ),
        ],
      ),
    );
  }

  Widget _highlight(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: wineColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _StatTile {
  const _StatTile(this.label, this.value, this.hint);
  final String label;
  final String value;
  final String hint;
}
