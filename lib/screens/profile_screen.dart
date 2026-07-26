import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'safety_tips_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    bottomNavigationBar: const AppBottomNav(index: 3),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.paleBlue,
                  child: Icon(Icons.person, size: 34, color: AppTheme.blue),
                ),
                SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Community Member',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    Text('Cagayan de Oro City, PH'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _option(
          context,
          Icons.location_on_outlined,
          'Saved Location',
          'Cagayan de Oro City, PH',
          'Location settings will be connected to device location.',
        ),
        _option(
          context,
          Icons.history,
          'Report History',
          'View your submitted hazard reports',
          'No submitted reports yet.',
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.health_and_safety_outlined,
              color: AppTheme.blue,
            ),
            title: const Text('Safety Tips'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SafetyTipsScreen()),
            ),
          ),
        ),
        _option(
          context,
          Icons.settings_outlined,
          'Notification Settings',
          '',
          'Notification settings saved for this prototype.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _message(context, 'Profile preferences saved.'),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Preferences'),
        ),
      ],
    ),
  );

  static Widget _option(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    String message,
  ) => Card(
    child: ListTile(
      leading: Icon(icon, color: AppTheme.blue),
      title: Text(title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _message(context, message),
    ),
  );
  static void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
