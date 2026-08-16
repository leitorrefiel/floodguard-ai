import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/hazard_report.dart';

class HazardReportService {
  static const _storageKey = 'hazard_reports';

  Future<List<HazardReport>> getReports() async {
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
    final report = HazardReport(
      id: now.microsecondsSinceEpoch.toString(),
      type: type,
      severity: severity,
      location: location,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    final reports = await getReports();
    await _saveReports([report, ...reports]);
    return report;
  }

  Future<void> updateReport(HazardReport report) async {
    final reports = await getReports();
    final updated = report.copyWith(updatedAt: DateTime.now());
    await _saveReports(
      reports.map((item) => item.id == updated.id ? updated : item).toList(),
    );
  }

  Future<void> deleteReport(String id) async {
    final reports = await getReports();
    await _saveReports(reports.where((report) => report.id != id).toList());
  }

  Future<void> _saveReports(List<HazardReport> reports) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      reports.map((report) => jsonEncode(report.toJson())).toList(),
    );
  }
}
