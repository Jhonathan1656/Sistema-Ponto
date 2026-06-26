import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'admin_screen.dart';
import 'profile_screen.dart';
import '../services/api_service.dart';
import '../services/app_permission_service.dart';
import '../services/notification_service.dart';
import '../widgets/user_notification_bell.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final _apiService = ApiService();
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppPermissionService.requestStartupPermissions();
    });
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = await _apiService.getCurrentUser();
      setState(() {
        _isAdmin = user['role'] == 'admin' || user['role'] == 'manager';
      });
      NotificationService.registerCurrentDevice();
    } catch (e) {
      debugPrint('Erro ao carregar usuário: $e');
    }
  }

  List<Widget> get _screens => [
        const HomeScreen(),
        const DashboardScreen(),
        const HistoryScreen(),
        if (_isAdmin) const AdminScreen(),
        const ProfileScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          if (!_isAdmin)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              right: _selectedIndex == 0 ? 64 : 16,
              child: const UserNotificationBell(),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.timer), label: 'Ponto'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dash'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'Histórico'),
          if (_isAdmin)
            const BottomNavigationBarItem(
                icon: Icon(Icons.admin_panel_settings), label: 'Gestão'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
