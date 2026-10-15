import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _apiService = ApiService();
  List<dynamic> _records = [];
  bool _isLoading = true;
  
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _filterType = 'diário'; // diário, semanal, mensal

  // Cores da Empresa
  static const Color wineColor = Color(0xFF8B0000);

  @override
  void initState() {
    super.initState();
    _setInitialDates();
    _fetchRecords();
  }

  void _setInitialDates() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  Future<void> _fetchRecords() async {
    setState(() => _isLoading = true);
    try {
      final records = await _apiService.getTimeRecords(
        startDate: _startDate.toIso8601String(),
        endDate: _endDate.toIso8601String(),
      );
      setState(() => _records = records);
    } catch (e) {
      debugPrint('Erro histórico: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeFilter(String type) {
    setState(() {
      _filterType = type;
      final now = DateTime.now();
      if (type == 'diário') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (type == 'semanal') {
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(_startDate.year, _startDate.month, _startDate.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (type == 'mensal') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      }
    });
    _fetchRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HISTÓRICO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          _buildDateHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: wineColor))
                : _buildRecordsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: ['diário', 'semanal', 'mensal'].map((type) {
          final isSelected = _filterType == type;
          return Expanded(
            child: GestureDetector(
              onTap: () => _changeFilter(type),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? wineColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.3)),
                ),
                alignment: Alignment.center,
                child: Text(
                  type.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      width: double.infinity,
      color: Theme.of(context).cardColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(DateFormat('dd/MM').format(_startDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const Text(' ATÉ ', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(DateFormat('dd/MM').format(_endDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    if (_records.isEmpty) {
      return const Center(child: Text('Nenhum registro no período.', style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final r = _records[index];
        final time =
            DateFormat('HH:mm:ss').format(DateTime.parse(r['timestamp']).toLocal());
        final date =
            DateFormat('dd/MM/yyyy').format(DateTime.parse(r['timestamp']).toLocal());
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_getIcon(r['record_type']), color: _getColor(r['record_type']), size: 20),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_getLabel(r['record_type']), style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(date, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Roboto', fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        );
      },
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'check_in': return Icons.login;
      case 'check_out': return Icons.logout;
      case 'break_start': return Icons.coffee;
      case 'break_end': return Icons.directions_run;
      case 'entry_3': return Icons.more_time;
      case 'exit_3': return Icons.timer_off;
      default: return Icons.access_time;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'check_in': return Colors.green;
      case 'check_out': return wineColor;
      case 'break_start': return Colors.orange;
      case 'break_end': return Colors.blue;
      default: return Colors.grey;
    }
  }

  String _getLabel(String type) {
    switch (type) {
      case 'check_in': return 'Entrada';
      case 'check_out': return 'Saída';
      case 'break_start': return 'Pausa 1 (Início)';
      case 'break_end': return 'Pausa 1 (Retorno)';
      case 'entry_3': return 'Pausa 2 (Início)';
      case 'exit_3': return 'Pausa 2 (Retorno)';
      default: return type;
    }
  }
}
