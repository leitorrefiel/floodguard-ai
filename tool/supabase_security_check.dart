import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';

Future<void> main() async {
  final env = Platform.environment;
  final url = _required(env, 'SUPABASE_URL');
  final key = _required(env, 'SUPABASE_PUBLISHABLE_KEY');
  final owner = SupabaseClient(url, key);
  final other = SupabaseClient(url, key);
  final reportIds = <String>[];
  String? photoPath;

  try {
    final ownerUser = (await owner.auth.signInWithPassword(
      email: _required(env, 'SUPABASE_TEST_EMAIL'),
      password: _required(env, 'SUPABASE_TEST_PASSWORD'),
    )).user;
    final otherUser = (await other.auth.signInWithPassword(
      email: _required(env, 'SUPABASE_OTHER_TEST_EMAIL'),
      password: _required(env, 'SUPABASE_OTHER_TEST_PASSWORD'),
    )).user;
    if (ownerUser == null || otherUser == null) {
      throw StateError('Both test users must authenticate.');
    }
    stdout.writeln('[Supabase] two-user authentication success');

    final protected = await _createReport(
      owner,
      ownerUser.id,
      description: '[TEST] RLS ownership validation; not a real incident.',
    );
    reportIds.add(protected);
    stdout.writeln('[Supabase] RLS owner create success id=$protected');

    final updateResult = await other
        .from('hazard_reports')
        .update({'severity': 'Critical'})
        .eq('id', protected)
        .select('id');
    if ((updateResult as List).isNotEmpty) {
      throw StateError('Another user updated the owner report.');
    }
    final unchanged = await owner
        .from('hazard_reports')
        .select('severity')
        .eq('id', protected)
        .single();
    if (unchanged['severity'] != 'Low') {
      throw StateError('RLS update attempt changed the owner report.');
    }
    stdout.writeln('[Supabase] RLS cross-user update blocked');

    final deleteResult = await other
        .from('hazard_reports')
        .delete()
        .eq('id', protected)
        .select('id');
    if ((deleteResult as List).isNotEmpty) {
      throw StateError('Another user deleted the owner report.');
    }
    final stillPresent = await owner
        .from('hazard_reports')
        .select('id')
        .eq('id', protected)
        .maybeSingle();
    if (stillPresent == null) {
      throw StateError('Owner report disappeared after blocked delete.');
    }
    stdout.writeln('[Supabase] RLS cross-user delete blocked');

    photoPath = '${ownerUser.id}/$protected/security-check.jpg';
    await owner.storage
        .from('hazard-report-photos')
        .uploadBinary(
          photoPath,
          _testJpeg(),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    var crossUserPhotoBlocked = false;
    try {
      await other.storage.from('hazard-report-photos').remove([photoPath]);
      final bytes = await owner.storage
          .from('hazard-report-photos')
          .download(photoPath);
      crossUserPhotoBlocked = bytes.isNotEmpty;
    } on StorageException {
      crossUserPhotoBlocked = true;
    }
    if (!crossUserPhotoBlocked) {
      throw StateError('Another user removed the owner photo.');
    }
    stdout.writeln('[Supabase] RLS cross-user photo delete blocked');

    final missingCoordinates = await _createReport(
      owner,
      ownerUser.id,
      description:
          '[TEST] Missing-coordinate verification; not a real incident.',
    );
    reportIds.add(missingCoordinates);
    await _invoke(owner, 'verify-hazard-report', missingCoordinates);
    final insufficient = await owner
        .from('hazard_reports')
        .select('status, confidence_score, verification_reason')
        .eq('id', missingCoordinates)
        .single();
    if (insufficient['status'] != 'pending' ||
        insufficient['confidence_score'] != 0 ||
        !insufficient['verification_reason'].toString().contains(
          'Insufficient evidence',
        )) {
      throw StateError('Missing coordinates were not kept pending.');
    }
    stdout.writeln('[Supabase] scenario success name=insufficient-evidence');

    final first = await _createReport(
      owner,
      ownerUser.id,
      latitude: 14.98135,
      longitude: 120.88310,
      description: '[TEST] Duplicate baseline; not a real incident.',
    );
    reportIds.add(first);
    await _invoke(owner, 'verify-hazard-report', first);

    final duplicate = await _createReport(
      owner,
      ownerUser.id,
      latitude: 14.98135,
      longitude: 120.88310,
      description: '[TEST] Duplicate scenario; not a real incident.',
    );
    reportIds.add(duplicate);
    await _invoke(owner, 'verify-hazard-report', duplicate);
    final duplicateResult = await owner
        .from('hazard_reports')
        .select('status, verification_evidence')
        .eq('id', duplicate)
        .single();
    final evidence = duplicateResult['verification_evidence'] as Map;
    final nearby = evidence['nearby_reports'] as Map?;
    if (duplicateResult['status'] != 'suspicious' ||
        nearby?['same_user_duplicate'] != true) {
      throw StateError('Same-user rapid duplicate was not suspicious.');
    }
    stdout.writeln('[Supabase] scenario success name=same-user-duplicate');
  } catch (error) {
    stderr.writeln('[Supabase] security validation failed error=$error');
    exitCode = 1;
  } finally {
    if (photoPath != null) {
      try {
        await owner.storage.from('hazard-report-photos').remove([photoPath]);
      } catch (_) {}
    }
    for (final id in reportIds.reversed) {
      try {
        await owner.from('hazard_reports').delete().eq('id', id);
      } catch (_) {}
    }
    await owner.dispose();
    await other.dispose();
  }
}

Future<String> _createReport(
  SupabaseClient client,
  String userId, {
  required String description,
  double? latitude,
  double? longitude,
}) async {
  final row = await client
      .from('hazard_reports')
      .insert({
        'user_id': userId,
        'type': 'floodedRoad',
        'severity': 'Low',
        'location': 'Automated validation - not a real incident',
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'status': 'pending',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
      })
      .select('id')
      .single();
  return row['id'].toString();
}

Future<void> _invoke(
  SupabaseClient client,
  String functionName,
  String reportId,
) async {
  final response = await client.functions.invoke(
    functionName,
    body: {'report_id': reportId},
  );
  if (response.status < 200 || response.status >= 300) {
    throw StateError('$functionName returned HTTP ${response.status}.');
  }
}

String _required(Map<String, String> env, String name) {
  final value = env[name]?.trim();
  if (value == null || value.isEmpty) throw StateError('$name is required.');
  return value;
}

Uint8List _testJpeg() => base64Decode(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==',
);
