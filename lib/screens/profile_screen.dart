import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  static const _avatarBucket = 'profile-pictures';

  final _client = Supabase.instance.client;
  final _imagePicker = ImagePicker();

  _ProfileDetails _profile = const _ProfileDetails();
  String? _avatarUrl;
  bool _isLoadingProfile = true;
  bool _isSavingProfile = false;
  bool _isUpdatingAccount = false;

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
      avatarPath: _text(metadata['avatar_path'] ?? metadata['avatar_url']),
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
    await _refreshAvatarUrl(details.avatarPath);
  }

  Future<void> _editProfile() async {
    final result = await showModalBottomSheet<_ProfileEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _EditProfileSheet(
        initialProfile: _profile,
        maxDisplayNameLength: _maxDisplayNameLength,
        imagePicker: _imagePicker,
        avatarUrl: _avatarUrl,
      ),
    );
    if (result == null) return;
    await _saveProfile(result);
  }

  Future<void> _saveProfile(_ProfileEditResult edit) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _message('Sign in to update your profile.');
      return;
    }

    setState(() => _isSavingProfile = true);
    try {
      var avatarPath = _profile.avatarPath;
      if (edit.removeAvatar) {
        await _removeAvatar(user.id, avatarPath);
        avatarPath = '';
      }
      if (edit.selectedImagePath != null) {
        avatarPath = await _uploadAvatar(user.id, edit.selectedImagePath!);
      }
      final details = _ProfileDetails(
        displayName: edit.displayName,
        avatarPath: avatarPath,
      );
      final savedProfile = await _saveProfileRecord(user, details);
      if (!mounted) return;
      setState(() => _profile = savedProfile);
      await _refreshAvatarUrl(savedProfile.avatarPath);
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
      'avatar_path': fallback.avatarPath.isEmpty ? null : fallback.avatarPath,
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
          .select('display_name, avatar_path')
          .eq('id', userId)
          .maybeSingle();
    } catch (error) {
      if (_missingColumn(error) != 'avatar_path') rethrow;
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
      'avatar_path': details.avatarPath.isEmpty ? null : details.avatarPath,
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
    var includeAvatar = true;

    while (true) {
      try {
        return await _client
            .from('profiles')
            .update(compatibleValues)
            .eq('id', userId)
            .select(_profileSelect(includeAvatar))
            .maybeSingle();
      } catch (error) {
        if (_isNoRows(error)) return null;
        final missingColumn = _missingColumn(error);
        if (missingColumn == null) rethrow;
        if (missingColumn == 'avatar_path') includeAvatar = false;
        if (!compatibleValues.containsKey(missingColumn)) rethrow;
        compatibleValues.remove(missingColumn);
      }
    }
  }

  Future<Map<String, dynamic>> _insertProfile(
    Map<String, Object?> values,
  ) async {
    final compatibleValues = Map<String, Object?>.from(values);
    var includeAvatar = true;

    while (true) {
      try {
        return await _client
            .from('profiles')
            .insert(compatibleValues)
            .select(_profileSelect(includeAvatar))
            .single();
      } catch (error) {
        final missingColumn = _missingColumn(error);
        if (missingColumn == null) rethrow;
        if (missingColumn == 'avatar_path') includeAvatar = false;
        if (!compatibleValues.containsKey(missingColumn)) rethrow;
        compatibleValues.remove(missingColumn);
      }
    }
  }

  String _profileSelect(bool includeAvatar) =>
      includeAvatar ? 'display_name, avatar_path' : 'display_name';

  Future<String> _uploadAvatar(String userId, String imagePath) async {
    final path = '$userId/avatar.jpg';
    await _client.storage
        .from(_avatarBucket)
        .upload(
          path,
          io.File(imagePath),
          fileOptions: const FileOptions(
            cacheControl: '3600',
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return path;
  }

  Future<void> _removeAvatar(String userId, String avatarPath) async {
    final path = avatarPath.isEmpty ? '$userId/avatar.jpg' : avatarPath;
    try {
      await _client.storage.from(_avatarBucket).remove([path]);
    } on StorageException catch (error) {
      debugPrint('Profile avatar removal unavailable: ${error.message}');
    }
  }

  Future<void> _refreshAvatarUrl(String avatarPath) async {
    if (avatarPath.isEmpty) {
      if (!mounted) return;
      setState(() => _avatarUrl = null);
      return;
    }
    try {
      final url = await _client.storage
          .from(_avatarBucket)
          .createSignedUrl(avatarPath, 60 * 60);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (error) {
      debugPrint('Profile avatar load unavailable: $error');
      if (!mounted) return;
      setState(() => _avatarUrl = null);
    }
  }

  Future<void> _changeEmail() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _ChangeEmailSheet(
        currentEmail: _client.auth.currentUser?.email ?? '',
      ),
    );
    if (result == null) return;

    setState(() => _isUpdatingAccount = true);
    try {
      await _client.auth.updateUser(UserAttributes(email: result));
      _message('Check your new email address to confirm the change.');
    } on AuthException catch (error) {
      _message(error.message);
    } catch (error) {
      debugPrint('Email update unavailable: $error');
      _message('Email update is unavailable right now.');
    } finally {
      if (mounted) setState(() => _isUpdatingAccount = false);
    }
  }

  Future<void> _changePassword() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _ChangePasswordSheet(),
    );
    if (result == null) return;

    setState(() => _isUpdatingAccount = true);
    try {
      await _client.auth.updateUser(UserAttributes(password: result));
      _message('Password updated successfully.');
    } on AuthException catch (error) {
      _message(error.message);
    } catch (error) {
      debugPrint('Password update unavailable: $error');
      _message('Password update is unavailable right now.');
    } finally {
      if (mounted) setState(() => _isUpdatingAccount = false);
    }
  }

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
                    _ProfileAvatar(avatarUrl: _avatarUrl, radius: 48),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                      child: Text(
                        'Account Security',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _SecurityActionRow(
                      icon: Icons.email_outlined,
                      title: 'Change Email',
                      onTap: _isUpdatingAccount ? null : _changeEmail,
                    ),
                    _SecurityActionRow(
                      icon: Icons.lock_outline,
                      title: 'Change Password',
                      onTap: _isUpdatingAccount ? null : _changePassword,
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
    required this.imagePicker,
    required this.avatarUrl,
  });

  final _ProfileDetails initialProfile;
  final int maxDisplayNameLength;
  final ImagePicker imagePicker;
  final String? avatarUrl;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  String? _selectedImagePath;
  bool _removeAvatar = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialProfile.displayName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await widget.imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      imageQuality: 86,
    );
    if (picked == null) return;
    setState(() {
      _selectedImagePath = picked.path;
      _removeAvatar = false;
    });
  }

  void _removePhoto() {
    setState(() {
      _selectedImagePath = null;
      _removeAvatar = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasPhoto =
        _selectedImagePath != null ||
        (!_removeAvatar && (widget.avatarUrl?.isNotEmpty ?? false));
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
              Center(
                child: Column(
                  children: [
                    _ProfileAvatar(
                      avatarUrl: _removeAvatar ? null : widget.avatarUrl,
                      localImagePath: _selectedImagePath,
                      radius: 46,
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(hasPhoto ? 'Replace Photo' : 'Choose Photo'),
                    ),
                    if (hasPhoto)
                      TextButton.icon(
                        onPressed: _removePhoto,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove Photo'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    Navigator.pop(
                      context,
                      _ProfileEditResult(
                        displayName: _text(_name.text),
                        selectedImagePath: _selectedImagePath,
                        removeAvatar: _removeAvatar,
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
  const _ProfileDetails({this.displayName = '', this.avatarPath = ''});

  factory _ProfileDetails.fromJson(Map<String, dynamic> json) =>
      _ProfileDetails(
        displayName: _text(json['display_name']),
        avatarPath: _text(json['avatar_path'] ?? json['avatar_url']),
      );

  final String displayName;
  final String avatarPath;
}

class _ProfileEditResult {
  const _ProfileEditResult({
    required this.displayName,
    required this.selectedImagePath,
    required this.removeAvatar,
  });

  final String displayName;
  final String? selectedImagePath;
  final bool removeAvatar;
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.radius,
    this.avatarUrl,
    this.localImagePath,
  });

  final double radius;
  final String? avatarUrl;
  final String? localImagePath;

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? image;
    if (localImagePath != null) {
      image = FileImage(io.File(localImagePath!));
    } else if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      image = NetworkImage(avatarUrl!);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.paleBlue,
      backgroundImage: image,
      child: image == null
          ? Icon(Icons.person, size: radius * 1.05, color: AppTheme.blue)
          : null,
    );
  }
}

class _SecurityActionRow extends StatelessWidget {
  const _SecurityActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: onTap != null,
    leading: Icon(icon, color: AppTheme.blue),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _ChangeEmailSheet extends StatefulWidget {
  const _ChangeEmailSheet({required this.currentEmail});

  final String currentEmail;

  @override
  State<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<_ChangeEmailSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
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
              const _SheetHandle(),
              const SizedBox(height: 22),
              Text(
                'Change Email',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Current Email',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(widget.currentEmail),
              const SizedBox(height: 18),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'New Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final text = _text(value);
                  if (text.isEmpty || !text.contains('@')) {
                    return 'Enter a valid email address.';
                  }
                  if (text.toLowerCase() == widget.currentEmail.toLowerCase()) {
                    return 'Enter a different email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    Navigator.pop(context, _text(_email.text));
                  },
                  child: const Text('Update Email'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
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
              const _SheetHandle(),
              const SizedBox(height: 22),
              Text(
                'Change Password',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value != null && value.length >= 8
                    ? null
                    : 'Use at least 8 characters.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                obscureText: _obscureConfirm,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Confirm your new password.';
                  }
                  return value == _password.text
                      ? null
                      : 'Passwords do not match.';
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    Navigator.pop(context, _password.text);
                  },
                  child: const Text('Update Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}

String _text(Object? value) => value?.toString().trim() ?? '';
