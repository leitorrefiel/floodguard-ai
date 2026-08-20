import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hazard_report.dart';

class HazardReportService {
  static const _storageKey = 'hazard_reports';
  static const _tableName = 'hazard_reports';

  HazardReportService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  String _storageLabel = 'Local device storage';

  String get storageLabel => _storageLabel;

  Future<List<HazardReport>> getReports() async {
    final remoteReports = await _tryApiRead();
    if (remoteReports != null) {
      _storageLabel = 'Supabase API';
      await _saveLocalReports(remoteReports);
      return remoteReports;
    }

    _storageLabel = 'Local device storage';
    return _getLocalReports();
  }

  Future<List<HazardReport>> _getLocalReports() async {
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(_storageKey) ?? const [];
    final reports = values
        .map((value) => jsonDecode(value) as Map<String, dynamic>)
        .map(HazardReport.fromJson)
        .toList();
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports;
  }

  Future<HazardReport> createReport({
    required HazardType type,
    required String severity,
    required String location,
    required String description,
  }) async {
    final now = DateTime.now();
    final localDraft = HazardReport(
      id: now.microsecondsSinceEpoch.toString(),
      type: type,
      severity: severity,
      location: location,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    final apiReport = await _tryApiCreate(localDraft);
    if (apiReport != null) {
      _storageLabel = 'Supabase API';
      final reports = await _getLocalReports();
      await _saveLocalReports([apiReport, ...reports]);
      return apiReport;
    }

    _storageLabel = 'Local device storage';
    final reports = await _getLocalReports();
    await _saveLocalReports([localDraft, ...reports]);
    return localDraft;
  }

  Future<void> updateReport(HazardReport report) async {
    final updated = report.copyWith(updatedAt: DateTime.now());
    final apiUpdated = await _tryApiUpdate(updated);
    _storageLabel = apiUpdated ? 'Supabase API' : 'Local device storage';
    final reports = await _getLocalReports();
    await _saveLocalReports(
      reports.map((item) => item.id == updated.id ? updated : item).toList(),
    );
  }

  Future<void> deleteReport(String id) async {
    final apiDeleted = await _tryApiDelete(id);
    _storageLabel = apiDeleted ? 'Supabase API' : 'Local device storage';
    final reports = await _getLocalReports();
    await _saveLocalReports(reports.where((report) => report.id != id).toList());
  }

  Future<List<HazardReport>?> _tryApiRead() async {
    try {
      final userId = _client.auth.currentUser?.id;
      final query = _client.from(_tableName).select();
      final data = userId == null
          ? await query.order('created_at', ascending: false)
          : await query.eq('user_id', userId).order(
              'created_at',
              ascending: false,
            );
      return (data as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(HazardReport.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<HazardReport?> _tryApiCreate(HazardReport report) async {
    try {
      final data = await _client
          .from(_tableName)
          .insert(report.toApiInsertJson(userId: _client.auth.currentUser?.id))
          .select()
          .single();
      return HazardReport.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _tryApiUpdate(HazardReport report) async {
    try {
      await _client
          .from(_tableName)
          .update(report.toApiUpdateJson())
          .eq('id', report.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryApiDelete(String id) async {
    try {
      await _client.from(_tableName).delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveLocalReports(List<HazardReport> reports) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      reports.map((report) => jsonEncode(report.toJson())).toList(),
    );
  }
}
