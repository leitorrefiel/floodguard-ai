import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _maxDisplayNameLength = 60;

  final _client = Supabase.instance.client;

  _ProfileDetails _profile = const _ProfileDetails();
  bool _isLoadingProfile = true;
  bool _isSavingProfile = false;

  @override
  void initState() {
    super.initState();
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
    );

    try {
      details = await _ensureProfile(user, fallback: details);
    } catch (error) {
      debugPrint('Profile load unavailable: $error');
    }

    if (!mounted) return;
    setState(() {
      _profile = details;
      _isLoadingProfile = false;
    });
  }

  Future<void> _editProfile() async {
    final result = await showModalBottomSheet<_ProfileDetails>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _EditProfileSheet(
        initialProfile: _profile,
        maxDisplayNameLength: _maxDisplayNameLength,
      ),
    );
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
      final savedProfile = await _saveProfileRecord(user, details);
      if (!mounted) return;
      setState(() => _profile = savedProfile);
      _message('Profile updated.');
    } catch (error) {
      debugPrint('Profile save unavailable: $error');
      if (!mounted) return;
      _message('Profile editing is unavailable right now.');
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<_ProfileDetails> _ensureProfile(
    User user, {
    required _ProfileDetails fallback,
  }) async {
    final existing = await _fetchProfile(user.id);
    if (existing != null) return existing;

    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'id': user.id,
      'display_name': fallback.displayName.isEmpty
          ? null
          : fallback.displayName,
      'phone_number': fallback.phoneNumber.isEmpty
          ? null
          : fallback.phoneNumber,
      'created_at': now,
      'updated_at': now,
    };
    final data = await _insertProfile(values);

    return _ProfileDetails.fromJson(data);
  }

  Future<_ProfileDetails?> _fetchProfile(String userId) async {
    Map<String, dynamic>? data;
    try {
      data = await _client
          .from('profiles')
          .select('display_name, phone_number')
          .eq('id', userId)
          .maybeSingle();
    } catch (error) {
      if (_missingColumn(error) != 'phone_number') rethrow;
      data = await _client
          .from('profiles')
          .select('display_name')
          .eq('id', userId)
          .maybeSingle();
    }
    return data == null ? null : _ProfileDetails.fromJson(data);
  }

  Future<_ProfileDetails> _saveProfileRecord(
    User user,
    _ProfileDetails details,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {
      'display_name': details.displayName.isEmpty ? null : details.displayName,
      'phone_number': details.phoneNumber.isEmpty ? null : details.phoneNumber,
      'updated_at': now,
    };

    final updated = await _updateProfile(user.id, values);
    if (updated != null) return _ProfileDetails.fromJson(updated);

    final inserted = await _insertProfile({
      'id': user.id,
      ...values,
      'created_at': now,
    });
    return _ProfileDetails.fromJson(inserted);
  }

  Future<Map<String, dynamic>?> _updateProfile(
    String userId,
    Map<String, Object?> values,
  ) async {
    final compatibleValues = Map<String, Object?>.from(values);
    var includePhone = true;

    while (true) {
      try {
        return await _client
            .from('profiles')
            .update(compatibleValues)
            .eq('id', userId)
            .select(_profileSelect(includePhone))
            .maybeSingle();
      } catch (error) {
        if (_isNoRows(error)) return null;
        final missingColumn = _missingColumn(error);
        if (missingColumn == null) rethrow;
        if (missingColumn == 'phone_number') includePhone = false;
        if (!compatibleValues.containsKey(missingColumn)) rethrow;
        compatibleValues.remove(missingColumn);
      }
    }
  }

  Future<Map<String, dynamic>> _insertProfile(
    Map<String, Object?> values,
  ) async {
    final compatibleValues = Map<String, Object?>.from(values);
    var includePhone = true;

    while (true) {
      try {
        return await _client
            .from('profiles')
            .insert(compatibleValues)
            .select(_profileSelect(includePhone))
            .single();
      } catch (error) {
        final missingColumn = _missingColumn(error);
        if (missingColumn == null) rethrow;
        if (missingColumn == 'phone_number') includePhone = false;
        if (!compatibleValues.containsKey(missingColumn)) rethrow;
        compatibleValues.remove(missingColumn);
      }
    }
  }

  String _profileSelect(bool includePhone) =>
      includePhone ? 'display_name, phone_number' : 'display_name';

  String? _missingColumn(Object error) {
    if (error is! PostgrestException) return null;
    final postgresMissingColumn = RegExp(
      r'column profiles\.([a-z_]+) does not exist',
    ).firstMatch(error.message);
    if (postgresMissingColumn != null) {
      return postgresMissingColumn.group(1);
    }
    return RegExp(
      "Could not find the '([^']+)' column",
    ).firstMatch(error.message)?.group(1);
  }

  bool _isNoRows(Object error) =>
      error is PostgrestException && error.message.contains('PGRST116');

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _confirmLogOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out of FloodGuard?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final email = _client.auth.currentUser?.email ?? '';
    final displayName = _profile.displayName.trim();
    final primaryName = displayName.isEmpty ? 'Community Member' : displayName;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      bottomNavigationBar: const AppBottomNav(index: 3),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 48,
                      backgroundColor: AppTheme.paleBlue,
                      child: Icon(Icons.person, size: 52, color: AppTheme.blue),
                    ),
                    const SizedBox(height: 18),
                    if (_isLoadingProfile)
                      const SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(minHeight: 4),
                      )
                    else
                      Text(
                        primaryName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSavingProfile ? null : _editProfile,
                      icon: _isSavingProfile
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_outlined),
                      label: const Text('Edit Profile'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _confirmLogOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Color(0xFFFFCDD2)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialProfile,
    required this.maxDisplayNameLength,
  });

  final _ProfileDetails initialProfile;
  final int maxDisplayNameLength;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialProfile.displayName);
    _phone = TextEditingController(text: widget.initialProfile.phoneNumber);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 10, 22, bottomInset + 22),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Edit Profile',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                maxLength: widget.maxDisplayNameLength,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  final text = _text(value);
                  if (text.length > widget.maxDisplayNameLength) {
                    return 'Use ${widget.maxDisplayNameLength} characters or fewer.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) {
                  final text = _text(value);
                  if (text.isEmpty) return null;
                  final valid = RegExp(r'^[0-9+\-\s()]{7,20}$').hasMatch(text);
                  return valid ? null : 'Enter a valid phone number.';
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    Navigator.pop(
                      context,
                      _ProfileDetails(
                        displayName: _text(_name.text),
                        phoneNumber: _text(_phone.text),
                      ),
                    );
                  },
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileDetails {
  const _ProfileDetails({this.displayName = '', this.phoneNumber = ''});

  factory _ProfileDetails.fromJson(Map<String, dynamic> json) =>
      _ProfileDetails(
        displayName: _text(json['display_name']),
        phoneNumber: _text(json['phone_number'] ?? json['phone']),
      );

  final String displayName;
  final String phoneNumber;
}

String _text(Object? value) => value?.toString().trim() ?? '';
