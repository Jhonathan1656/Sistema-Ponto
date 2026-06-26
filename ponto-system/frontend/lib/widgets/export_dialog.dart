import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/export_service.dart';

class ExportDialog extends StatefulWidget {
  final Map<String, dynamic>? initialUser;
  final bool isScratch;
  final bool htmlOnly;

  const ExportDialog({
    super.key,
    this.initialUser,
    this.isScratch = false,
    this.htmlOnly = false,
  });

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  final _apiService = ApiService();
  final _exportService = ExportService();

  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _deptController = TextEditingController();
  final _targetHoursController = TextEditingController();

  String?
      _selectedExportType; // 'Lote: APENAS ESTAGIÁRIOS', 'Individual: Jonathan', etc.
  List<dynamic> _users = [];
  bool _isLoadingData = true;
  bool _isProcessing = false;

  DateTime _selectedDate = DateTime.now();
  String _closingMode = 'calendar';
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _roleController.text = 'Aux. Geral';
    _deptController.text = 'Campo';
    _targetHoursController.text = '210';

    if (widget.isScratch) {
      _nameController.text = '';
      _isLoadingData = false;
    } else {
      _fetchUsers();
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final users = await _apiService.getUsers();
      setState(() {
        _users = users;
        _isLoadingData = false;

        if (widget.htmlOnly) {
          _selectedExportType = 'Lote: TODOS';
        } else if (widget.initialUser != null) {
          final selectedUser = _findLoadedUser(widget.initialUser!);
          _selectedExportType = 'Individual: ${selectedUser['name']}';
          _applySelectedUserDefaults(selectedUser);
        } else {
          _selectedExportType = 'Lote: TODOS';
        }
      });
    } catch (e) {
      debugPrint('Erro fetch users: $e');
      setState(() => _isLoadingData = false);
    }
  }

  Future<void> _handleExport() async {
    final holidays = await _askHolidayDays();
    if (holidays == null) return;

    Map<String, bool>? estagRules;
    final individualUser = _selectedIndividualUser();
    if (individualUser != null && _isIntern(individualUser)) {
      estagRules = await _askEstagRules();
      if (estagRules == null) return;
    }

    setState(() => _isProcessing = true);
    try {
      final period = _selectedPeriod();
      final month = _selectedDate.month.toString().padLeft(2, '0');
      final year = _selectedDate.year.toString();
      final start =
          DateTime(period.start.year, period.start.month, period.start.day)
              .toIso8601String();
      final end = DateTime(
              period.end.year, period.end.month, period.end.day, 23, 59, 59)
          .toIso8601String();
      final periodStart = period.start.toIso8601String();
      final periodEnd = period.end.toIso8601String();
      final periodLabel = period.label;
      final useCustomPeriod = _closingMode != 'calendar';

      if (widget.isScratch) {
        // Modo Avulso (Do 0)
        final data = {
          'employee': {
            'name': _nameController.text,
            'role': _roleController.text
          },
          'daily_records': [],
          'custom_role': _roleController.text,
          'custom_department': _deptController.text,
          'custom_work_hours': null,
          'generate_from_scratch': true,
          'target_hours': double.tryParse(_targetHoursController.text) ?? 210.0,
          'holidays': holidays,
        };

        await _exportService.exportToExcel(
          data: data,
          month: month,
          year: year,
          isCampo: true,
          periodStart: useCustomPeriod ? periodStart : null,
          periodEnd: useCustomPeriod ? periodEnd : null,
          periodLabel: useCustomPeriod ? periodLabel : null,
        );
      } else {
        // Modo Normal (Registros do App)
        if (widget.htmlOnly || _selectedExportType!.startsWith('Lote:')) {
          final usersToExport = _selectedUsersForExport();

          List<Map<String, dynamic>> reports = [];
          for (final rawUser in usersToExport) {
            final user = Map<String, dynamic>.from(rawUser);
            final data = await _apiService.exportTimesheet(
                startDate: start, endDate: end, userId: user['id']);
            reports.add({
              ...data,
              'custom_role': _exportJobTitle(user),
              'custom_department': _exportDepartment(user),
              'custom_work_hours': _exportWorkHours(user),
              'generate_from_scratch': false,
              'target_hours': _exportTargetHours(user),
              'holidays': holidays,
            });
          }
          if (widget.htmlOnly) {
            await _exportService.exportBatchToHtml(
              reports: reports,
              month: month,
              year: year,
              periodStart: useCustomPeriod ? periodStart : null,
              periodEnd: useCustomPeriod ? periodEnd : null,
              periodLabel: useCustomPeriod ? periodLabel : null,
            );
          } else {
            await _exportService.exportBatchToZip(
              reports: reports,
              month: month,
              year: year,
              periodStart: useCustomPeriod ? periodStart : null,
              periodEnd: useCustomPeriod ? periodEnd : null,
              periodLabel: useCustomPeriod ? periodLabel : null,
            );
          }
        } else {
          // Individual
          final userName =
              _selectedExportType!.replaceFirst('Individual: ', '');
          final user = Map<String, dynamic>.from(
              _users.firstWhere((u) => u['name'] == userName));
          final data = await _apiService.exportTimesheet(
              startDate: start, endDate: end, userId: user['id']);

          await _exportService.exportToExcel(
            data: {
              ...data,
              'custom_role': _exportJobTitle(user),
              'custom_department': _exportDepartment(user),
              'custom_work_hours': _exportWorkHours(user),
              'generate_from_scratch': false,
              'target_hours': _exportTargetHours(user),
              'holidays': holidays,
              if (estagRules != null) 'estag_rules': estagRules,
            },
            month: month,
            year: year,
            isCampo: !_isIntern(user),
            periodStart: useCustomPeriod ? periodStart : null,
            periodEnd: useCustomPeriod ? periodEnd : null,
            periodLabel: useCustomPeriod ? periodLabel : null,
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Exportação concluída!'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: const Color(0xFF8B0000)));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _exportJobTitle(Map<String, dynamic> user) {
    final role = (user['role'] ?? '').toString().toLowerCase();
    if (role == 'intern' || role.contains('estag')) return 'Estagiario';

    final savedTitle = user['job_title']?.toString().trim();
    if (savedTitle != null && savedTitle.isNotEmpty) return savedTitle;

    final typedTitle = _roleController.text.trim();
    if (typedTitle.isNotEmpty) return typedTitle;

    return 'Aux. Geral';
  }

  List<dynamic> _selectedUsersForExport() {
    if (_selectedExportType == 'Lote: APENAS ESTAGIÁRIOS') {
      return _users
          .where((u) => _isIntern(Map<String, dynamic>.from(u)))
          .toList();
    }

    if (_selectedExportType == 'Lote: APENAS CAMPO') {
      return _users
          .where((u) => !_isIntern(Map<String, dynamic>.from(u)))
          .toList();
    }

    if (_selectedExportType != null &&
        _selectedExportType!.startsWith('Individual: ')) {
      final userName = _selectedExportType!.replaceFirst('Individual: ', '');
      return _users.where((u) => u['name'] == userName).toList();
    }

    return _users;
  }

  Map<String, dynamic>? _selectedIndividualUser() {
    if (widget.isScratch ||
        _selectedExportType == null ||
        !_selectedExportType!.startsWith('Individual: ')) {
      return null;
    }

    final userName = _selectedExportType!.replaceFirst('Individual: ', '');
    try {
      return Map<String, dynamic>.from(
          _users.firstWhere((u) => u['name'] == userName));
    } catch (_) {
      return null;
    }
  }

  bool _isIntern(Map<String, dynamic> user) {
    final role = (user['role'] ?? '').toString().toLowerCase();
    return role == 'intern' || role.contains('estag');
  }

  String _exportDepartment(Map<String, dynamic> user) {
    return _isIntern(user) ? 'Processamento de Dados' : 'Campo';
  }

  String _exportWorkHours(Map<String, dynamic> user) {
    return _isIntern(user) ? '13:30 - 19:30' : '-';
  }

  double _exportTargetHours(Map<String, dynamic> user) {
    final dailyHours = double.tryParse(user['daily_hours']?.toString() ?? '');
    if (dailyHours == null || dailyHours <= 0) return 210.0;
    return dailyHours * 30;
  }

  ({DateTime start, DateTime end, String label}) _selectedPeriod() {
    final month = _selectedDate.month;
    final year = _selectedDate.year;

    if (_closingMode == 'cutoff28') {
      final start = DateTime(year, month - 1, 29);
      final end = DateTime(year, month, 28);
      return (
        start: start,
        end: end,
        label:
            '${_formatDate(start)} a ${_formatDate(end)} - compet. ${month.toString().padLeft(2, '0')}/$year'
      );
    }

    if (_closingMode == 'custom') {
      final start = _customStartDate ?? DateTime(year, month, 1);
      final end = _customEndDate ?? DateTime(year, month + 1, 0);
      return (
        start: start,
        end: end,
        label:
            '${_formatDate(start)} a ${_formatDate(end)} - compet. ${month.toString().padLeft(2, '0')}/$year'
      );
    }

    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    return (
      start: start,
      end: end,
      label: '${month.toString().padLeft(2, '0')}/$year'
    );
  }

  String _formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  Future<void> _pickCustomDate({required bool start}) async {
    final currentPeriod = _selectedPeriod();
    final initialDate = start ? currentPeriod.start : currentPeriod.end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() {
      if (start) {
        _customStartDate = picked;
        if (_customEndDate != null && _customEndDate!.isBefore(picked)) {
          _customEndDate = picked;
        }
      } else {
        _customEndDate = picked;
        if (_customStartDate != null && _customStartDate!.isAfter(picked)) {
          _customStartDate = picked;
        }
      }
    });
  }

  Future<List<int>?> _askHolidayDays() async {
    final hasHoliday = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feriados no mês'),
        content: const Text('Teve algum feriado nesse mês?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B0000)),
            child: const Text('Sim', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (hasHoliday == null) return null;
    if (!hasHoliday) return [];
    if (!mounted) return null;

    return _askHolidayInput();
  }

  Future<List<int>?> _askHolidayInput() async {
    final controller = TextEditingController();
    String? errorText;
    final period = _selectedPeriod();
    final maxDay = period.end.difference(period.start).inDays + 1;

    final result = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Informe os feriados'),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Dias do mês',
                  helperText: 'Ex: 11 ou 11, 20',
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final parsed = _parseHolidayDays(controller.text, maxDay);
                    if (parsed == null || parsed.isEmpty) {
                      setDialogState(() {
                        errorText = 'Informe dias válidos entre 1 e $maxDay.';
                      });
                      return;
                    }
                    Navigator.pop(dialogContext, parsed);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B0000)),
                  child: const Text('Continuar',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  List<int>? _parseHolidayDays(String input, int maxDay) {
    final days = <int>{};
    final pieces = input.split(RegExp(r'[^0-9]+'));

    for (final piece in pieces) {
      if (piece.trim().isEmpty) continue;
      final day = int.tryParse(piece);
      if (day == null || day < 1 || day > maxDay) return null;
      days.add(day);
    }

    final sortedDays = days.toList()..sort();
    return sortedDays;
  }

  Future<Map<String, bool>?> _askEstagRules() async {
    bool saturday50 = true;
    bool sunday100 = true;
    bool night100 = true;

    return showDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Regras do estagiário'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: saturday50,
                    onChanged: (value) =>
                        setDialogState(() => saturday50 = value ?? true),
                    title: const Text('Sábado 50%'),
                    subtitle: const Text(
                        'Desmarcado: horas de sábado viram normais.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: sunday100,
                    onChanged: (value) =>
                        setDialogState(() => sunday100 = value ?? true),
                    title: const Text('Domingo e feriado 100%'),
                    subtitle: const Text(
                        'Desmarcado: domingo e feriado viram normais.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: night100,
                    onChanged: (value) =>
                        setDialogState(() => night100 = value ?? true),
                    title: const Text('Noturno 100%'),
                    subtitle:
                        const Text('Desmarcado: horas noturnas viram normais.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, {
                    'saturday_50': saturday50,
                    'sunday_100': sunday100,
                    'night_100': night100,
                  }),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B0000)),
                  child: const Text('Continuar',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _findLoadedUser(Map<String, dynamic> fallback) {
    final fallbackId = fallback['id']?.toString();
    if (fallbackId != null) {
      for (final rawUser in _users) {
        final user = Map<String, dynamic>.from(rawUser);
        if (user['id']?.toString() == fallbackId) return user;
      }
    }

    final fallbackName = fallback['name']?.toString();
    if (fallbackName != null) {
      for (final rawUser in _users) {
        final user = Map<String, dynamic>.from(rawUser);
        if (user['name']?.toString() == fallbackName) return user;
      }
    }

    return fallback;
  }

  void _applySelectedUserDefaults(Map<String, dynamic> user) {
    _roleController.text = _exportJobTitle(user);
    _deptController.text = _exportDepartment(user);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) return const Center(child: CircularProgressIndicator());

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
          widget.htmlOnly
              ? 'Gerar Folha de Ponto .html'
              : (widget.isScratch
                  ? 'Gerar Folha Avulsa'
                  : 'Configurar Exportação'),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isScratch
                  ? 'Cria horários automáticos para uma pessoa não cadastrada:'
                  : widget.htmlOnly
                      ? 'Escolha pessoa, mês e ano para gerar o HTML.'
                      : 'Escolha pessoa, mês e ano para exportar:',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (widget.isScratch) ...[
              _buildTextField(_nameController, 'Nome Completo'),
              const SizedBox(height: 12),
            ] else ...[
              _buildExportTypeDropdown(),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(child: _buildMonthDropdown()),
                const SizedBox(width: 12),
                Expanded(child: _buildYearDropdown()),
              ],
            ),
            const SizedBox(height: 12),
            _buildClosingModeDropdown(),
            const SizedBox(height: 8),
            _buildPeriodPreview(),
            if (_closingMode == 'custom') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildDateButton(
                      label: 'Inicio',
                      value: _selectedPeriod().start,
                      onTap: () => _pickCustomDate(start: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDateButton(
                      label: 'Fim',
                      value: _selectedPeriod().end,
                      onTap: () => _pickCustomDate(start: false),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.isScratch) ...[
              const SizedBox(height: 12),
              _buildTextField(_roleController, 'Função'),
              const SizedBox(height: 12),
              _buildTextField(_deptController, 'Departamento'),
              const SizedBox(height: 12),
              _buildTextField(
                  _targetHoursController, 'Carga Horária (ex: 210)'),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar',
                      style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _handleExport,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      widget.isScratch ? Colors.blue : const Color(0xFF8B0000),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        widget.htmlOnly
                            ? 'Gerar HTML'
                            : (widget.isScratch
                                ? 'Gerar e Baixar'
                                : 'Confirmar Exportação'),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedExportType,
          dropdownColor: const Color(0xFF1E1E1E),
          isExpanded: true,
          style: const TextStyle(color: Colors.white),
          items: [
            const DropdownMenuItem(
                value: 'Lote: APENAS ESTAGIÁRIOS',
                child: Text('Lote: APENAS ESTAGIÁRIOS')),
            const DropdownMenuItem(
                value: 'Lote: APENAS CAMPO', child: Text('Lote: APENAS CAMPO')),
            const DropdownMenuItem(
                value: 'Lote: TODOS', child: Text('Lote: TODOS')),
            const DropdownMenuItem(
                enabled: false,
                value: 'sep',
                child: Divider(color: Colors.white24)),
            ..._users.map((u) => DropdownMenuItem(
                value: 'Individual: ${u['name']}',
                child: Text('Individual: ${u['name']}'))),
          ],
          onChanged: (val) {
            if (val == 'sep') return;
            setState(() {
              _selectedExportType = val;
              if (val != null && val.startsWith('Individual: ')) {
                final userName = val.replaceFirst('Individual: ', '');
                final user = Map<String, dynamic>.from(
                    _users.firstWhere((u) => u['name'] == userName));
                _applySelectedUserDefaults(user);
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildClosingModeDropdown() {
    return _buildDropdown(
      label: 'Fechamento',
      value: _closingMode,
      items: const [
        DropdownMenuItem(value: 'calendar', child: Text('Mes calendario')),
        DropdownMenuItem(value: 'cutoff28', child: Text('29 a 28')),
        DropdownMenuItem(value: 'custom', child: Text('Personalizado')),
      ],
      onChanged: (val) {
        if (val == null) return;
        setState(() => _closingMode = val);
      },
    );
  }

  Widget _buildPeriodPreview() {
    final period = _selectedPeriod();
    return Text(
      'Periodo: ${_formatDate(period.start)} ate ${_formatDate(period.end)}',
      style: const TextStyle(color: Colors.grey, fontSize: 12),
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text('$label: ${_formatDate(value)}'),
    );
  }

  Widget _buildMonthDropdown() {
    return _buildDropdown(
      label: 'Mês',
      value: _selectedDate.month.toString().padLeft(2, '0'),
      items: List.generate(12, (i) {
        final m = (i + 1).toString().padLeft(2, '0');
        return DropdownMenuItem(value: m, child: Text(m));
      }),
      onChanged: (val) {
        setState(() =>
            _selectedDate = DateTime(_selectedDate.year, int.parse(val!)));
      },
    );
  }

  Widget _buildYearDropdown() {
    return _buildDropdown(
      label: 'Ano',
      value: _selectedDate.year.toString(),
      items: ['2023', '2024', '2025', '2026']
          .map((y) => DropdownMenuItem(value: y, child: Text(y)))
          .toList(),
      onChanged: (val) {
        setState(() =>
            _selectedDate = DateTime(int.parse(val!), _selectedDate.month));
      },
    );
  }

  Widget _buildDropdown(
      {required String label,
      required String value,
      required List<DropdownMenuItem<String>> items,
      required Function(String?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: const Color(0xFF1E1E1E),
              isDense: true,
              style: const TextStyle(color: Colors.white),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.white24),
            borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.blue),
            borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
    );
  }
}
