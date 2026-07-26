import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'risk_details_screen.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alerts')),
    bottomNavigationBar: const AppBottomNav(index: 1),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Stay informed about flood conditions near you.'),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFFFFF5F5),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFE3E3),
              child: Icon(Icons.warning_amber_rounded, color: Colors.red),
            ),
            title: const Text('Flood Watch'),
            subtitle: const Text(
              'Moderate to heavy rainfall expected within the next 24 hours.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const RiskDetailsScreen(),
              ),
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.paleBlue,
              child: Icon(Icons.cloudy_snowing, color: AppTheme.blue),
            ),
            title: Text('Rainfall Update'),
            subtitle: Text('36 mm rainfall recorded during the last 24 hours.'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.paleBlue,
              child: Icon(Icons.people_outline, color: AppTheme.blue),
            ),
            title: Text('Community Report Verified'),
            subtitle: Text('A flooded road report in Baliwag was verified.'),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All current alerts are marked as read.'),
            ),
          ),
          icon: const Icon(Icons.done_all),
          label: const Text('Mark All as Read'),
        ),
      ],
    ),
  );
}
