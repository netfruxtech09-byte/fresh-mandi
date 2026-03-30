import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import 'auth_screens.dart';
import 'dashboard_tab.dart';
import 'goods_screens.dart';
import 'quality_screens.dart';
import 'routes_screens.dart';

class ProcessingHomeShell extends StatefulWidget {
  const ProcessingHomeShell({super.key});

  @override
  State<ProcessingHomeShell> createState() => _ProcessingHomeShellState();
}

class _ProcessingHomeShellState extends State<ProcessingHomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final tabs = <ShellTab>[
      const ShellTab(
        title: 'Dashboard',
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        child: DashboardTab(),
      ),
      if (auth.canUseInbound)
        const ShellTab(
          title: 'Goods',
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2,
          child: GoodsReceivedTab(),
        ),
      if (auth.canUseQuality)
        const ShellTab(
          title: 'Quality',
          icon: Icons.fact_check_outlined,
          activeIcon: Icons.fact_check,
          child: QualityQueueTab(),
        ),
      if (auth.canUseRoutes)
        const ShellTab(
          title: 'Routes',
          icon: Icons.route_outlined,
          activeIcon: Icons.route,
          child: RoutesTab(),
        ),
    ];

    final safeIndex = _selectedIndex.clamp(0, tabs.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: Text(tabs[safeIndex].title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                auth.roleCode.replaceAll('_', ' '),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ),
          IconButton(
            onPressed: () async {
              await auth.logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: tabs[safeIndex].child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (value) =>
            setState(() => _selectedIndex = value),
        destinations: tabs
            .map(
              (tab) => NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.activeIcon),
                label: tab.title,
              ),
            )
            .toList(),
      ),
    );
  }
}

class ShellTab {
  const ShellTab({
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final IconData activeIcon;
  final Widget child;
}
