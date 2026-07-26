import 'package:flutter/material.dart';

import '../screens/alerts_screen.dart';
import '../screens/forecast_screen.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../utils/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.index});

  final int index;

  void _onTap(BuildContext context, int value) {
    if (value == index) return;
    if (value == 0) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else if (value == 1) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AlertsScreen()));
    } else if (value == 2) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ForecastScreen()));
    } else if (value == 3) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: index,
    onDestinationSelected: (value) => _onTap(context, value),
    indicatorColor: AppTheme.paleBlue,
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(Icons.notifications_none),
        selectedIcon: Icon(Icons.notifications),
        label: 'Alerts',
      ),
      NavigationDestination(
        icon: Icon(Icons.show_chart),
        selectedIcon: Icon(Icons.show_chart),
        label: 'Forecast',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
    ],
  );
}
