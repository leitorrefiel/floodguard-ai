import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_location_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'report_hazard_screen.dart';
import 'safety_tips_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _locationService = DeviceLocationService();
  String _location = 'Getting device location...';
  String? _coordinates;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshLocation();
  }

  Future<void> _refreshLocation() async {
    setState(() => _isLoading = true);
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _location = location.label;
        _coordinates =
            '${location.latitude.toStringAsFixed(5)}° N, ${location.longitude.toStringAsFixed(5)}° E';
      });
    } on LocationAccessException catch (error) {
      _setUnavailable(error.message);
    } catch (_) {
      _setUnavailable('Location unavailable. Tap Saved Location to retry.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setUnavailable(String message) {
    if (!mounted) return;
    setState(() {
      _location = message;
      _coordinates = null;
    });
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    bottomNavigationBar: const AppBottomNav(index: 3),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.paleBlue,
                  child: Icon(Icons.person, size: 34, color: AppTheme.blue),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Supabase.instance.client.auth.currentUser?.email ??
                            'Community Member',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        _location,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.location_on_outlined,
              color: AppTheme.blue,
            ),
            title: const Text('Saved Location'),
            subtitle: Text(
              _coordinates == null ? _location : '$_location\n$_coordinates',
            ),
            isThreeLine: _coordinates != null,
            trailing: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location, color: AppTheme.blue),
            onTap: _isLoading ? null : _refreshLocation,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.history, color: AppTheme.blue),
            title: const Text('Report History'),
            subtitle: const Text('View your submitted hazard reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ReportHazardScreen(),
              ),
            ),
          ),
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
          Icons.settings_outlined,
          'Notification Settings',
          '',
          'Notification settings saved for this prototype.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _message('Profile preferences saved.'),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Preferences'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );

  Widget _option(
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
      onTap: () => _message(message),
    ),
  );
}
