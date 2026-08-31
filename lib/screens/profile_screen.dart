import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_location_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'alerts_screen.dart';
import 'report_hazard_screen.dart';
import 'safety_tips_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _locationService = DeviceLocationService();
  final _client = Supabase.instance.client;

  String _location = 'Getting device location...';
  String? _coordinates;
  _ProfileDetails _profile = const _ProfileDetails();
  bool _isLoadingLocation = true;
  bool _isLoadingProfile = true;
  bool _isSavingProfile = false;

  @override
  void initState() {
    super.initState();
    _refreshLocation();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoadingProfile = false);
      return;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    var details = _ProfileDetails(
      displayName: _text(metadata['display_name'] ?? metadata['full_name']),
      phoneNumber: _text(metadata['phone_number'] ?? metadata['phone']),
      emergencyContactName: _text(metadata['emergency_contact_name']),
      emergencyContactPhone: _text(metadata['emergency_contact_phone']),
    );

    try {
      final data = await _client
          .from('profiles')
          .select(
            'display_name, phone_number, emergency_contact_name, emergency_contact_phone',
          )
          .eq('id', user.id)
          .maybeSingle();
      if (data != null) details = _ProfileDetails.fromJson(data);
    } catch (_) {
      // Keep auth metadata fallback when profile details are unavailable.
    }

    if (!mounted) return;
    setState(() {
      _profile = details;
      _isLoadingProfile = false;
    });
  }

  Future<void> _refreshLocation({bool showMessage = false}) async {
    setState(() => _isLoadingLocation = true);
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _location = location.label;
        _coordinates =
            '${location.latitude.toStringAsFixed(5)}° N, ${location.longitude.toStringAsFixed(5)}° E';
      });
      if (showMessage) _message('Saved location updated.');
    } on LocationAccessException catch (error) {
      _setUnavailable(error.message);
    } catch (_) {
      _setUnavailable('Location unavailable. Try again when GPS is available.');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
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

  Future<void> _editProfile() async {
    final name = TextEditingController(text: _profile.displayName);
    final phone = TextEditingController(text: _profile.phoneNumber);
    final emergencyName = TextEditingController(
      text: _profile.emergencyContactName,
    );
    final emergencyPhone = TextEditingController(
      text: _profile.emergencyContactPhone,
    );

    final result = await showDialog<_ProfileDetails>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emergencyName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Contact name',
                  prefixIcon: Icon(Icons.contact_emergency_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emergencyPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact phone',
                  prefixIcon: Icon(Icons.phone_in_talk_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _ProfileDetails(
                displayName: name.text.trim(),
                phoneNumber: phone.text.trim(),
                emergencyContactName: emergencyName.text.trim(),
                emergencyContactPhone: emergencyPhone.text.trim(),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    name.dispose();
    phone.dispose();
    emergencyName.dispose();
    emergencyPhone.dispose();
    if (result == null) return;
    await _saveProfile(result);
  }

  Future<void> _saveProfile(_ProfileDetails details) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _message('Sign in to update your profile.');
      return;
    }
    setState(() => _isSavingProfile = true);
    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'display_name': details.displayName,
        'phone_number': details.phoneNumber,
        'emergency_contact_name': details.emergencyContactName,
        'emergency_contact_phone': details.emergencyContactPhone,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
      if (!mounted) return;
      setState(() => _profile = details);
      _message('Profile updated.');
    } catch (_) {
      if (!mounted) return;
      _message('Profile editing is unavailable right now.');
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of FloodGuard?'),
        content: const Text('You can sign in again to access your reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = _client.auth.currentUser?.email;
    final displayName = _profile.displayName.trim();
    final primaryName = displayName.isEmpty ? 'Community Member' : displayName;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      bottomNavigationBar: const AppBottomNav(index: 3),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionLabel('Profile'),
          const SizedBox(height: 8),
          _profileHeader(primaryName: primaryName, email: email),
          const SizedBox(height: 16),
          _SectionLabel('Saved Location'),
          const SizedBox(height: 8),
          _savedLocationCard(),
          const SizedBox(height: 16),
          _SectionLabel('Activity'),
          const SizedBox(height: 8),
          _actionCard(
            icon: Icons.history,
            title: 'Report History',
            subtitle: 'View your submitted hazard reports',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ReportHazardScreen(),
              ),
            ),
          ),
          _actionCard(
            icon: Icons.fact_check_outlined,
            title: 'Safety Checklist',
            subtitle: 'View and update your emergency preparedness items',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SafetyTipsScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('Preferences'),
          const SizedBox(height: 8),
          _actionCard(
            icon: Icons.notifications_active_outlined,
            title: 'Notification Settings',
            subtitle: 'Manage FloodGuard alert preferences',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
            ),
          ),
          if (_profile.hasEmergencyContact) ...[
            const SizedBox(height: 16),
            _SectionLabel('Emergency Information'),
            const SizedBox(height: 8),
            _emergencyInfoCard(),
          ],
          const SizedBox(height: 16),
          _SectionLabel('Account'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _confirmSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Color(0xFFFFCDD2)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Widget _profileHeader({
    required String primaryName,
    required String? email,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.paleBlue,
            child: Icon(Icons.person, size: 36, color: AppTheme.blue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoadingProfile)
                  const LinearProgressIndicator(minHeight: 4)
                else
                  Text(
                    primaryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                if (email != null && email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _location,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isSavingProfile ? null : _editProfile,
            icon: _isSavingProfile
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_outlined),
            tooltip: 'Edit profile',
          ),
        ],
      ),
    ),
  );

  Widget _savedLocationCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, color: AppTheme.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (_coordinates != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _coordinates!,
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (_isLoadingLocation)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Used for flood monitoring, alerts, and nearby safety information.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _isLoadingLocation
                    ? null
                    : () => _refreshLocation(showMessage: true),
                icon: const Icon(Icons.my_location),
                label: const Text('Use Current Location'),
              ),
              OutlinedButton.icon(
                onPressed: _isLoadingLocation
                    ? null
                    : () => _refreshLocation(showMessage: true),
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Change Location'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    child: ListTile(
      leading: Icon(icon, color: AppTheme.blue),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );

  Widget _emergencyInfoCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.contact_emergency_outlined, color: AppTheme.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_profile.emergencyContactName.isNotEmpty)
                  Text(
                    _profile.emergencyContactName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                if (_profile.emergencyContactPhone.isNotEmpty)
                  Text(_profile.emergencyContactPhone),
                const SizedBox(height: 6),
                const Text(
                  'Visible only on your profile.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: _editProfile, child: const Text('Edit')),
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _ProfileDetails {
  const _ProfileDetails({
    this.displayName = '',
    this.phoneNumber = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
  });

  factory _ProfileDetails.fromJson(Map<String, dynamic> json) =>
      _ProfileDetails(
        displayName: _text(json['display_name']),
        phoneNumber: _text(json['phone_number'] ?? json['phone']),
        emergencyContactName: _text(json['emergency_contact_name']),
        emergencyContactPhone: _text(json['emergency_contact_phone']),
      );

  final String displayName;
  final String phoneNumber;
  final String emergencyContactName;
  final String emergencyContactPhone;

  bool get hasEmergencyContact =>
      emergencyContactName.isNotEmpty || emergencyContactPhone.isNotEmpty;
}

String _text(Object? value) => value?.toString().trim() ?? '';
