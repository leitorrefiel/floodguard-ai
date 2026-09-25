import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final url = _required(environment, 'SUPABASE_URL');
  final key = _required(environment, 'SUPABASE_PUBLISHABLE_KEY');
  final email = _required(environment, 'SUPABASE_TEST_EMAIL');
  final password = _required(environment, 'SUPABASE_TEST_PASSWORD');
  final client = SupabaseClient(url, key);

  String? reportId;
  String? hazardPhotoPath;
  String? profilePhotoPath;
  try {
    final auth = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = auth.user;
    if (user == null) throw StateError('Authentication returned no user.');
    stdout.writeln('[Supabase] connected host=${Uri.parse(url).host}');
    stdout.writeln('[Supabase] authentication success user=${user.id}');

    await _verifyTables(client);

    final created = await client
        .from('hazard_reports')
        .insert({
          'user_id': user.id,
          'type': 'other',
          'severity': 'Low',
          'location': 'Automated backend validation - no real location',
          'description':
              '[TEST] Temporary backend validation record; not a real hazard incident.',
          'status': 'pending',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .toIso8601String(),
          'other_hazard_type': 'Backend validation',
        })
        .select()
        .single();
    reportId = created['id']?.toString();
    if (reportId == null || reportId.isEmpty) {
      throw StateError('CREATE returned no report id.');
    }
    stdout.writeln('[Supabase] create success id=$reportId');

    final read = await client
        .from('hazard_reports')
        .select()
        .eq('id', reportId)
        .single();
    if (read['user_id'] != user.id) {
      throw StateError('READ returned a report owned by another user.');
    }
    stdout.writeln('[Supabase] read success id=$reportId');

    const updatedDescription =
        '[TEST] Updated backend validation record; not a real hazard incident.';
    final updated = await client
        .from('hazard_reports')
        .update({
          'description': updatedDescription,
          'severity': 'Moderate',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', reportId)
        .select('id, description, severity')
        .single();
    if (updated['description'] != updatedDescription ||
        updated['severity'] != 'Moderate') {
      throw StateError('UPDATE values were not persisted.');
    }
    stdout.writeln('[Supabase] update success id=$reportId');

    final jpeg = _testJpeg();
    hazardPhotoPath = '${user.id}/$reportId/backend-validation.jpg';
    await client.storage
        .from('hazard-report-photos')
        .uploadBinary(
          hazardPhotoPath,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    final hazardSignedUrl = await client.storage
        .from('hazard-report-photos')
        .createSignedUrl(hazardPhotoPath, 300);
    if (!hazardSignedUrl.startsWith('http')) {
      throw StateError('Hazard photo signed URL was invalid.');
    }
    stdout.writeln('[Supabase] storage success bucket=hazard-report-photos');

    await client.storage
        .from('hazard-report-photos')
        .updateBinary(
          hazardPhotoPath,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    stdout.writeln(
      '[Supabase] storage replacement success bucket=hazard-report-photos',
    );

    profilePhotoPath = '${user.id}/backend-validation.jpg';
    await client.storage
        .from('profile-pictures')
        .uploadBinary(
          profilePhotoPath,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    final profileSignedUrl = await client.storage
        .from('profile-pictures')
        .createSignedUrl(profilePhotoPath, 300);
    if (!profileSignedUrl.startsWith('http')) {
      throw StateError('Profile picture signed URL was invalid.');
    }
    stdout.writeln('[Supabase] storage success bucket=profile-pictures');

    await client.storage
        .from('profile-pictures')
        .updateBinary(
          profilePhotoPath,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    stdout.writeln(
      '[Supabase] storage replacement success bucket=profile-pictures',
    );

    final photoFunction = await client.functions.invoke(
      'verify-hazard-photo',
      body: {'photo_url': hazardSignedUrl, 'reported_category': 'other'},
    );
    _requireFunctionSuccess('verify-hazard-photo', photoFunction);

    final reportFunction = await client.functions.invoke(
      'verify-hazard-report',
      body: {'report_id': reportId},
    );
    _requireFunctionSuccess('verify-hazard-report', reportFunction);
    final verification = await client
        .from('hazard_reports')
        .select('status, confidence_score, verification_reason')
        .eq('id', reportId)
        .single();
    if (verification['status'] != 'pending' ||
        verification['confidence_score'] != 0 ||
        !verification['verification_reason'].toString().contains(
          'Insufficient evidence',
        )) {
      throw StateError(
        'Missing coordinates were not retained as insufficient evidence.',
      );
    }
    stdout.writeln(
      '[Supabase] verification scenario success name=insufficient-evidence',
    );

    final confirmation = await client
        .from('report_confirmations')
        .insert({'report_id': reportId, 'user_id': user.id})
        .select('id')
        .single();
    if (confirmation['id'] == null) {
      throw StateError('Confirmation insert returned no id.');
    }
    stdout.writeln('[Supabase] table verified name=report_confirmations');

    await _deleteReport(client, reportId);
    reportId = null;
  } catch (error) {
    stderr.writeln('[Supabase] validation failed error=$error');
    exitCode = 1;
  } finally {
    if (hazardPhotoPath != null) {
      await _bestEffortRemove(client, 'hazard-report-photos', hazardPhotoPath);
    }
    if (profilePhotoPath != null) {
      await _bestEffortRemove(client, 'profile-pictures', profilePhotoPath);
    }
    if (reportId != null) await _bestEffortDeleteReport(client, reportId);
    await client.dispose();
  }
}

Future<void> _verifyTables(SupabaseClient client) async {
  const probes = <String, String>{
    'profiles': 'id',
    'hazard_reports': 'id',
    'report_confirmations': 'id',
    'notification_preferences': 'user_id',
    'push_devices': 'id',
    'alerts': 'id',
  };
  for (final entry in probes.entries) {
    await client.from(entry.key).select(entry.value).limit(1);
    stdout.writeln('[Supabase] table verified name=${entry.key}');
  }
}

Future<void> _deleteReport(SupabaseClient client, String reportId) async {
  final deleted = await client
      .from('hazard_reports')
      .delete()
      .eq('id', reportId)
      .select('id')
      .maybeSingle();
  if (deleted == null) throw StateError('DELETE affected no rows.');
  final remaining = await client
      .from('hazard_reports')
      .select('id')
      .eq('id', reportId)
      .maybeSingle();
  if (remaining != null) throw StateError('Deleted report is still readable.');
  stdout.writeln('[Supabase] delete success id=$reportId');
}

void _requireFunctionSuccess(String name, FunctionResponse response) {
  if (response.status < 200 || response.status >= 300) {
    throw StateError(
      '$name returned HTTP ${response.status}: ${response.data}',
    );
  }
  stdout.writeln('[Supabase] edge function success name=$name');
}

Future<void> _bestEffortRemove(
  SupabaseClient client,
  String bucket,
  String path,
) async {
  try {
    await client.storage.from(bucket).remove([path]);
  } catch (error) {
    stderr.writeln('[Supabase] cleanup warning bucket=$bucket error=$error');
  }
}

Future<void> _bestEffortDeleteReport(
  SupabaseClient client,
  String reportId,
) async {
  try {
    await client.from('hazard_reports').delete().eq('id', reportId);
  } catch (error) {
    stderr.writeln('[Supabase] cleanup warning report=$reportId error=$error');
  }
}

String _required(Map<String, String> environment, String name) {
  final value = environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required.');
  }
  return value;
}

Uint8List _testJpeg() => base64Decode(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==',
);
