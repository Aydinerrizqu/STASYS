import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/train')) return 0;
    if (location.startsWith('/history')) return 1;
    if (location.startsWith('/tracking')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/train');
        break;
      case 1:
        context.go('/history');
        break;
      case 2:
        context.go('/tracking');
        break;
      case 3:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: StsysTheme.mobileBackground,
          border: Border(
            top: BorderSide(color: StsysTheme.mobileBorder, width: 1),
          ),
        ),
        child: Row(
          children: [
            _NavTab(
              icon: Icons.fitness_center,
              label: 'Train',
              isSelected: selectedIndex == 0,
              onTap: () => _onItemTapped(context, 0),
            ),
            _NavTab(
              icon: Icons.history_outlined,
              label: 'History',
              isSelected: selectedIndex == 1,
              onTap: () => _onItemTapped(context, 1),
            ),
            _NavTab(
              icon: Icons.gps_fixed_outlined,
              label: 'Tracking',
              isSelected: selectedIndex == 2,
              onTap: () => _onItemTapped(context, 2),
            ),
            _NavTab(
              icon: Icons.settings_outlined,
              label: 'Settings',
              isSelected: selectedIndex == 3,
              onTap: () => _onItemTapped(context, 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? StsysTheme.cyan : StsysTheme.mobileMutedText,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? StsysTheme.cyan
                    : StsysTheme.mobileMutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
