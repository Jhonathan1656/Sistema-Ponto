import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/api_service.dart';
import 'team_records_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  // Cores da Empresa
  static const Color wineColor = Color(0xFF8B0000);
  final _apiService = ApiService();
  bool _isAdmin = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    try {
      final user = await _apiService.getCurrentUser();
      setState(() {
        _isAdmin = user['role'] == 'admin';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar cargo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Center(child: CircularProgressIndicator(color: wineColor));

    return DefaultTabController(
      length: _isAdmin ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PAINEL DO GESTOR',
              style:
                  TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          bottom: TabBar(
            labelColor: wineColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: wineColor,
            tabs: [
              const Tab(icon: Icon(Icons.monitor_heart), text: 'Resumo'),
              const Tab(icon: Icon(Icons.people), text: 'Usuários'),
              const Tab(icon: Icon(Icons.list_alt), text: 'Registros'),
              if (_isAdmin)
                const Tab(
                    icon: Icon(Icons.add_circle_outline), text: 'Add Ponto'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _TeamStatusTab(),
            const _UsersListTab(),
            TeamRecordsScreen(canEdit: _isAdmin),
            if (_isAdmin) const _ManualEntryTab(),
          ],
        ),
      ),
    );
  }
}

class _UsersListTab extends StatefulWidget {
  const _UsersListTab();

  @override
  State<_UsersListTab> createState() => _UsersListTabState();
}

class _UsersListTabState extends State<_UsersListTab> {
  final _apiService = ApiService();
  List<dynamic> _users = [];
  bool _isLoading = true;
  bool _isAdmin = false;

  static const Color wineColor = Color(0xFF8B0000);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _apiService.getCurrentUser();
      _isAdmin = user['role'] == 'admin';
      await _fetchUsers();
    } catch (e) {
      debugPrint('Erro init usuários: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final users = await _apiService.getUsers();
      setState(() => _users = users);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: wineColor),
        );
      }
    }
  }

  void _editUser(dynamic user) {
    showDialog(
      context: context,
      builder: (context) => UserEditDialog(
        user: user,
        onSave: () => _fetchUsers(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Center(child: CircularProgressIndicator(color: wineColor));

    return RefreshIndicator(
      onRefresh: _fetchUsers,
      color: wineColor,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final user = _users[index];
          String role = user['role'] ?? '-';
          if (role == 'intern') role = 'Estagiário';
          if (role == 'employee') role = 'Funcionário';
          final jobTitle = (user['job_title'] ?? role).toString();

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: wineColor,
                child: Text(user['name'][0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(user['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('$role • $jobTitle • ${user['daily_hours']}h/dia',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: _isAdmin
                  ? const Icon(Icons.edit, color: wineColor, size: 20)
                  : null,
              onTap: _isAdmin ? () => _editUser(user) : null,
            ),
          );
        },
      ),
    );
  }
}

class _TeamStatusTab extends StatefulWidget {
  const _TeamStatusTab();

  @override
  State<_TeamStatusTab> createState() => _TeamStatusTabState();
}

class _TeamStatusTabState extends State<_TeamStatusTab> {
  final _apiService = ApiService();
  static const Color wineColor = Color(0xFF8B0000);

  bool _isLoading = true;
  List<Map<String, dynamic>> _summaries = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _timer = Timer.periodic(
        const Duration(minutes: 1), (_) => _loadSummary(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadSummary({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);

    try {
      final users = await _apiService.getUsers();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toIso8601String();
      final end =
          DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();
      final records =
          await _apiService.getAdminTimeRecords(startDate: start, endDate: end);

      final recordsByUser = <String, List<Map<String, dynamic>>>{};
      for (final rawRecord in records) {
        final record = Map<String, dynamic>.from(rawRecord);
        final userId = record['user_id']?.toString();
        if (userId == null) continue;
        recordsByUser.putIfAbsent(userId, () => []).add(record);
      }

      final summaries = users.map<Map<String, dynamic>>((rawUser) {
        final user = Map<String, dynamic>.from(rawUser);
        final userRecords = recordsByUser[user['id']?.toString()] ?? [];
        userRecords.sort((a, b) =>
            (a['timestamp'] as String).compareTo(b['timestamp'] as String));
        return _buildUserSummary(user, userRecords, now);
      }).toList();

      summaries.sort((a, b) {
        const priority = {
          'working': 0,
          'paused_overdue': 1,
          'paused': 2,
          'done': 3,
          'none': 4
        };
        final pA = priority[a['status_key']] ?? 9;
        final pB = priority[b['status_key']] ?? 9;
        if (pA != pB) return pA.compareTo(pB);
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      if (mounted) {
        setState(() {
          _summaries = summaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro resumo equipe: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _buildUserSummary(
    Map<String, dynamic> user,
    List<Map<String, dynamic>> records,
    DateTime now,
  ) {
    Duration worked = Duration.zero;
    DateTime? workStart;

    for (final record in records) {
      final type = record['record_type']?.toString();
      final timestamp = DateTime.parse(record['timestamp']);

      if (type == 'check_in' || type == 'break_end' || type == 'exit_3') {
        workStart ??= timestamp;
      } else if (type == 'break_start' ||
          type == 'entry_3' ||
          type == 'check_out') {
        if (workStart != null && timestamp.isAfter(workStart)) {
          worked += timestamp.difference(workStart);
        }
        workStart = null;
      }
    }

    final lastRecord = records.isNotEmpty ? records.last : null;
    final lastType = lastRecord?['record_type']?.toString();
    final lastTime =
        lastRecord != null ? DateTime.parse(lastRecord['timestamp']) : null;

    String statusKey = 'none';
    String statusLabel = 'Sem ponto hoje';
    Color statusColor = Colors.grey;
    bool pauseOverdue = false;

    if (lastType == 'check_in' ||
        lastType == 'break_end' ||
        lastType == 'exit_3') {
      statusKey = 'working';
      statusLabel = 'Trabalhando agora';
      statusColor = Colors.green;
      if (workStart != null && now.isAfter(workStart)) {
        worked += now.difference(workStart);
      }
    } else if (lastType == 'break_start' || lastType == 'entry_3') {
      final pauseDuration =
          lastTime == null ? Duration.zero : now.difference(lastTime);
      pauseOverdue = pauseDuration.inMinutes >= 90;
      statusKey = pauseOverdue ? 'paused_overdue' : 'paused';
      statusLabel = pauseOverdue ? 'Pausa aberta ha mais de 1h30' : 'Em pausa';
      statusColor = pauseOverdue ? Colors.red : Colors.orange;
    } else if (lastType == 'check_out') {
      statusKey = 'done';
      statusLabel = 'Expediente encerrado';
      statusColor = wineColor;
    }

    return {
      'name': user['name']?.toString() ?? 'Sem nome',
      'role': user['role']?.toString() ?? '',
      'status_key': statusKey,
      'status_label': statusLabel,
      'status_color': statusColor,
      'worked': worked,
      'last_time': lastTime,
      'pause_overdue': pauseOverdue,
      'records_count': records.length,
    };
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours.toString().padLeft(2, '0')}h${minutes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: wineColor));
    }

    final workingCount =
        _summaries.where((s) => s['status_key'] == 'working').length;
    final pausedCount = _summaries
        .where((s) =>
            s['status_key'] == 'paused' || s['status_key'] == 'paused_overdue')
        .length;
    final overdueCount =
        _summaries.where((s) => s['pause_overdue'] == true).length;

    return RefreshIndicator(
      onRefresh: _loadSummary,
      color: wineColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        children: [
          Row(
            children: [
              _buildCounter('Trabalhando', workingCount, Colors.green),
              const SizedBox(width: 8),
              _buildCounter('Em pausa', pausedCount, Colors.orange),
              const SizedBox(width: 8),
              _buildCounter('Pausa longa', overdueCount, Colors.red),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'STATUS DA EQUIPE',
            style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 188,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _summaries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _buildEmployeeStatusCard(_summaries[index]),
            ),
          ),
          const SizedBox(height: 20),
          ..._summaries
              .where((summary) =>
                  summary['status_key'] == 'working' ||
                  summary['status_key'] == 'paused_overdue')
              .map(_buildPriorityRow),
        ],
      ),
    );
  }

  Widget _buildCounter(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: TextStyle(
                    color: color, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeStatusCard(Map<String, dynamic> summary) {
    final color = summary['status_color'] as Color;
    final lastTime = summary['last_time'] as DateTime?;
    final worked = summary['worked'] as Duration;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: color,
                child: Text(
                  (summary['name'] as String).isNotEmpty
                      ? (summary['name'] as String)[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary['name'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(summary['status_label'],
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          const Text('Horas hoje',
              style: TextStyle(color: Colors.grey, fontSize: 11)),
          Text(_formatDuration(worked),
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            lastTime == null
                ? 'Sem registros hoje'
                : 'Ultimo ponto ${DateFormat('HH:mm').format(lastTime)}',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityRow(Map<String, dynamic> summary) {
    final color = summary['status_color'] as Color;
    final worked = summary['worked'] as Duration;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
              summary['pause_overdue'] == true
                  ? Icons.warning_amber
                  : Icons.work,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(summary['status_label'],
                    style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
          ),
          Text(_formatDuration(worked),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class UserEditDialog extends StatefulWidget {
  final dynamic user;
  final VoidCallback onSave;

  const UserEditDialog({super.key, required this.user, required this.onSave});

  @override
  State<UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<UserEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _hoursController;
  late TextEditingController _jobTitleController;
  late String _selectedRole;
  final _apiService = ApiService();
  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.user['name']?.toString() ?? '');
    _hoursController =
        TextEditingController(text: widget.user['daily_hours'].toString());
    _selectedRole = widget.user['role'];
    _jobTitleController = TextEditingController(
      text: _initialJobTitle(_selectedRole, widget.user['job_title']),
    );
  }

  String _initialJobTitle(String role, dynamic savedTitle) {
    if (role == 'intern') return 'Estagiario';
    final title = savedTitle?.toString().trim();
    if (title != null && title.isNotEmpty) return title;
    return 'Aux. Geral';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hoursController.dispose();
    _jobTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar: ${widget.user['name']}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: 'Nome cadastrado',
                  labelStyle: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              dropdownColor: Theme.of(context).cardColor,
              decoration: const InputDecoration(
                  labelText: 'Cargo/Modelo',
                  labelStyle: TextStyle(color: Colors.grey)),
              items: const [
                DropdownMenuItem(
                    value: 'employee', child: Text('Funcionário (8h)')),
                DropdownMenuItem(
                    value: 'intern', child: Text('Estagiário (6h)')),
                DropdownMenuItem(value: 'manager', child: Text('Gestor')),
                DropdownMenuItem(value: 'admin', child: Text('Administrador')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedRole = val;
                    if (val == 'intern') {
                      _hoursController.text = '6.0';
                      _jobTitleController.text = 'Estagiario';
                    }
                    if (val == 'employee') {
                      _hoursController.text = '8.0';
                      if (_jobTitleController.text.trim().isEmpty ||
                          _jobTitleController.text.trim() == 'Estagiario') {
                        _jobTitleController.text = 'Aux. Geral';
                      }
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _jobTitleController,
              enabled: _selectedRole != 'intern',
              decoration: InputDecoration(
                labelText: 'Função na folha',
                helperText: _selectedRole == 'intern'
                    ? 'Estagiarios usam sempre Estagiario'
                    : 'Ex: Aux. Geral, Coordenador de Campo',
                labelStyle: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hoursController,
              decoration: const InputDecoration(
                  labelText: 'Carga Horária Diária',
                  labelStyle: TextStyle(color: Colors.grey)),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: (_isSaving || _isDeleting) ? null : _confirmDelete,
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          label: const Text('Excluir', style: TextStyle(color: Colors.red)),
        ),
        const SizedBox(width: 12),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B0000)),
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Salvar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe o nome do usuario.'),
            backgroundColor: Color(0xFF8B0000)),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _apiService.updateUserAdmin(
        widget.user['id'],
        name: name,
        email: widget.user['email']?.toString() ?? '',
        role: _selectedRole,
        jobTitle: _selectedRole == 'intern'
            ? 'Estagiario'
            : (_jobTitleController.text.trim().isEmpty
                ? 'Aux. Geral'
                : _jobTitleController.text.trim()),
        dailyHours: double.tryParse(_hoursController.text) ?? 8.0,
        cpf: widget.user['cpf']?.toString() ?? '',
      );
      widget.onSave();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro: $e'),
              backgroundColor: const Color(0xFF8B0000)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmController = TextEditingController();
    final userName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : widget.user['name']?.toString() ?? '';
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Excluir conta'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Isso removera "$userName" da lista de usuarios.'),
                  const SizedBox(height: 8),
                  const Text(
                    'Os registros de ponto antigos serao preservados para historico.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Text('Digite o nome para confirmar: $userName'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (confirmController.text.trim() != userName) {
                      setDialogState(() => errorText =
                          'Nome diferente. Confira e tente novamente.');
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Excluir conta',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    confirmController.dispose();
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await _apiService.deleteUserAdmin(widget.user['id']);
      widget.onSave();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Conta excluida da lista de usuarios.'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao excluir conta: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }
}

class _ManualEntryTab extends StatefulWidget {
  const _ManualEntryTab();

  @override
  State<_ManualEntryTab> createState() => _ManualEntryTabState();
}

class _ManualEntryTabState extends State<_ManualEntryTab> {
  final _apiService = ApiService();
  final _notesController = TextEditingController();

  List<dynamic> _users = [];
  dynamic _selectedUserId;
  DateTime _selectedDate = DateTime.now();

  TimeOfDay? _entryTime;
  TimeOfDay? _break1Start;
  TimeOfDay? _break1End;
  TimeOfDay? _break2Start;
  TimeOfDay? _break2End;
  TimeOfDay? _exitTime;

  bool _isLoadingUsers = true;
  bool _isSaving = false;

  static const Color wineColor = Color(0xFF8B0000);

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final users = await _apiService.getUsers();
      setState(() {
        _users = users;
        _isLoadingUsers = false;
      });
    } catch (e) {
      _showError('Erro ao carregar usuários: $e');
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: const Color(0xFF8B0000)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay? initial) async {
    return await showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 8, minute: 0),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context)
                  .colorScheme
                  .copyWith(primary: const Color(0xFF8B0000)),
            ),
            child: child!,
          ),
        );
      },
    );
  }

  Future<void> _saveBatch() async {
    if (_selectedUserId == null) {
      _showError('Selecione um funcionário');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final Map<String, TimeOfDay?> mappings = {
        'check_in': _entryTime,
        'break_start': _break1Start,
        'break_end': _break1End,
        'entry_3': _break2Start,
        'exit_3': _break2End,
        'check_out': _exitTime,
      };

      int count = 0;
      for (var entry in mappings.entries) {
        if (entry.value != null) {
          final timestamp = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            entry.value!.hour,
            entry.value!.minute,
          ).toIso8601String();

          await _apiService.createTimeRecord(
            recordType: entry.key,
            userId: _selectedUserId,
            timestamp: timestamp,
            notes: _notesController.text,
            location: 'Manual (Lote Gestor)',
          );
          count++;
        }
      }

      if (count > 0) {
        _showSuccess('$count registros adicionados com sucesso!');
        _clearForm();
      } else {
        _showError('Preencha pelo menos um horário');
      }
    } catch (e) {
      _showError('Erro ao salvar: $e\nVerifique as permissões do Firebase.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _clearForm() {
    setState(() {
      _entryTime = _break1Start =
          _break1End = _break2Start = _break2End = _exitTime = null;
      _notesController.clear();
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: wineColor));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUsers)
      return const Center(child: CircularProgressIndicator(color: wineColor));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LANÇAMENTO EM LOTE (DIA CHEIO)',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: Colors.grey)),
          const SizedBox(height: 24),
          DropdownButtonFormField<dynamic>(
            value: _selectedUserId,
            dropdownColor: Theme.of(context).cardColor,
            decoration: const InputDecoration(
                labelText: 'Funcionário',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder()),
            items: _users
                .map((u) =>
                    DropdownMenuItem(value: u['id'], child: Text(u['name'])))
                .toList(),
            onChanged: (val) => setState(() => _selectedUserId = val),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: wineColor),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Data do Registro',
                          style: TextStyle(color: Colors.grey, fontSize: 10)),
                      Text(DateFormat('dd/MM/yyyy').format(_selectedDate),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('HORÁRIOS DO DIA',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildTimeRow(
              '1. Entrada', _entryTime, (t) => setState(() => _entryTime = t)),
          _buildTimeRow('2. Pausa 1 (Início)', _break1Start,
              (t) => setState(() => _break1Start = t)),
          _buildTimeRow('3. Pausa 1 (Fim)', _break1End,
              (t) => setState(() => _break1End = t)),
          _buildTimeRow('4. Pausa 2 (Início)', _break2Start,
              (t) => setState(() => _break2Start = t)),
          _buildTimeRow('5. Pausa 2 (Fim)', _break2End,
              (t) => setState(() => _break2End = t)),
          _buildTimeRow(
              '6. Saída', _exitTime, (t) => setState(() => _exitTime = t)),
          const SizedBox(height: 24),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Observação do Gestor',
              labelStyle: TextStyle(color: Colors.grey),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isSaving ? null : _saveBatch,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B0000),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('LANÇAR DIA INTEIRO',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildTimeRow(
      String label, TimeOfDay? time, Function(TimeOfDay?) onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          final t = await _pickTime(time);
          if (t != null) onPick(t);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Row(
                children: [
                  Text(time?.format(context) ?? '--:--',
                      style: TextStyle(
                          color: time != null ? null : Colors.grey,
                          fontWeight: FontWeight.bold)),
                  if (time != null)
                    IconButton(
                      icon:
                          const Icon(Icons.close, size: 16, color: Colors.grey),
                      onPressed: () => onPick(null),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.only(left: 8),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
