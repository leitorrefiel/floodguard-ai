import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import 'hazard_image_verification_service.dart';
import 'report_verification_service.dart';
import 'weather_service.dart';

class HazardReportService {
  static const _storageKey = 'hazard_reports';
  static const _confirmationStorageKey = 'hazard_report_confirmations';
  static const _tableName = 'hazard_reports';
  static const _confirmationTableName = 'report_confirmations';
  static const _photoBucket = 'hazard-report-photos';
  static const _signedPhotoUrlSeconds = 60 * 60;

  HazardReportService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client {
    _imageVerificationService = HazardImageVerificationService(client: _client);
  }

  final SupabaseClient _client;
  late final HazardImageVerificationService _imageVerificationService;
  final ReportVerificationService _verificationService =
      ReportVerificationService();
  final WeatherService _weatherService = WeatherService();
  String _storageLabel = 'Local device storage';
  String? _lastPhotoUploadError;

  String get storageLabel => _storageLabel;
  String? get lastPhotoUploadError => _lastPhotoUploadError;

  Future<List<HazardReport>> getReports({
    bool includeCommunityReports = false,
  }) async {
    final remoteReports = await _tryApiRead(
      includeCommunityReports: includeCommunityReports,
    );
    if (remoteReports != null) {
      _storageLabel = 'Supabase API';
      await _saveLocalReports(
        remoteReports,
        includeCommunityReports: includeCommunityReports,
      );
      return remoteReports;
    }

    _storageLabel = 'Local device storage';
    _log('Supabase unavailable; using local cache/fallback reports.');
    return _getLocalReports(includeCommunityReports: includeCommunityReports);
  }

  Future<List<HazardReport>> _getLocalReports({
    bool includeCommunityReports = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final values =
        preferences.getStringList(
          _localStorageKey(includeCommunityReports: includeCommunityReports),
        ) ??
        const [];
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
    required double latitude,
    required double longitude,
    String? localPhotoPath,
    String? otherHazardType,
  }) async {
    final now = DateTime.now();
    final userId = _client.auth.currentUser?.id;
    final existingReports = await _getLocalReports();
    final localDraft = HazardReport(
      id: now.microsecondsSinceEpoch.toString(),
      type: type,
      severity: severity,
      location: location,
      description: description,
      latitude: latitude,
      longitude: longitude,
      photoUrl: null,
      status: HazardReportStatus.pending,
      isVerified: false,
      confidenceScore: 0,
      verificationState: HazardVerificationState.running,
      verificationReason: 'Automated credibility assessment is running.',
      verificationEvidence: const {
        'assessment': {'status': 'running'},
      },
      confirmationCount: 0,
      expiresAt: now.add(const Duration(days: 3)),
      otherHazardType: otherHazardType,
      userId: userId,
      createdAt: now,
      updatedAt: now,
    );
    final apiReport = await _tryApiCreate(localDraft);
    if (apiReport != null) {
      _storageLabel = 'Supabase API';
      var reportForVerification = apiReport;
      if (localPhotoPath != null && localPhotoPath.isNotEmpty) {
        reportForVerification = await _attachRemotePhoto(
          report: apiReport,
          localPhotoPath: localPhotoPath,
          createdAt: now,
        );
      }
      await _saveLocalReports([reportForVerification, ...existingReports]);
      return _runAutomatedVerification(reportForVerification);
    }

    _storageLabel = 'Local device storage';
    final localReport = localDraft.copyWith(photoUrl: localPhotoPath);
    await _saveLocalReports([localReport, ...existingReports]);
    return _runAutomatedVerification(localReport);
  }

  Future<HazardReport> updateReport(HazardReport report) async {
    final reports = await _getLocalReports();
    final pending = report.copyWith(
      status: HazardReportStatus.pending,
      isVerified: false,
      confidenceScore: 0,
      verificationState: HazardVerificationState.running,
      verificationReason: 'Automated credibility assessment is running.',
      verificationEvidence: const {
        'assessment': {'status': 'running'},
      },
      updatedAt: DateTime.now(),
    );
    final apiUpdated = await _tryApiUpdate(pending);
    _storageLabel = apiUpdated ? 'Supabase API' : 'Local device storage';
    var reportForVerification = pending;
    final candidatePhoto = report.photoUrl;
    if (apiUpdated &&
        candidatePhoto != null &&
        candidatePhoto.isNotEmpty &&
        !candidatePhoto.startsWith('http') &&
        await File(candidatePhoto).exists()) {
      reportForVerification = await _attachRemotePhoto(
        report: pending.copyWith(photoUrl: ''),
        localPhotoPath: candidatePhoto,
        createdAt: DateTime.now(),
      );
    }
    await _saveLocalReports(
      reports
          .map(
            (item) => item.id == reportForVerification.id
                ? reportForVerification
                : item,
          )
          .toList(),
    );
    return _runAutomatedVerification(reportForVerification);
  }

  Future<bool> confirmReport(HazardReport report) async {
    final confirmerId = _client.auth.currentUser?.id ?? 'local-anonymous';
    if (await _hasConfirmed(report.id, confirmerId)) return false;
    await _tryApiCreateConfirmation(report.id, confirmerId);
    await _saveLocalConfirmation(report.id, confirmerId);

    final withConfirmation = report.copyWith(
      confirmationCount: report.confirmationCount + 1,
      updatedAt: DateTime.now(),
    );
    final reports = await getReports(includeCommunityReports: true);
    final verification = await _verificationService.evaluate(
      withConfirmation,
      context: ReportVerificationContext(
        existingReports: reports,
        reporterId: report.userId,
        weather: report.hasCoordinate
            ? await _weatherFor(
                latitude: report.latitude!,
                longitude: report.longitude!,
              )
            : null,
      ),
    );
    final confirmed = _verificationService.applyResult(
      withConfirmation,
      verification,
    );
    final apiUpdated = await _tryApiUpdate(confirmed);
    _storageLabel = apiUpdated ? 'Supabase API' : 'Local device storage';
    await _saveLocalReports(
      reports
          .map((item) => item.id == confirmed.id ? confirmed : item)
          .toList(),
      includeCommunityReports: true,
    );
    return true;
  }

  Future<HazardReport> retryPhotoUpload({
    required HazardReport report,
    required String localPhotoPath,
  }) async {
    if (localPhotoPath.isEmpty) return report;
    if (report.id.isEmpty) return report;

    final apiUpdated = await _tryApiUpdate(report);
    _storageLabel = apiUpdated ? 'Supabase API' : 'Local device storage';
    if (!apiUpdated) {
      final localReport = report.copyWith(photoUrl: localPhotoPath);
      await _replaceReport(localReport);
      return _runAutomatedVerification(localReport);
    }

    final withPhoto = await _attachRemotePhoto(
      report: report.copyWith(photoUrl: ''),
      localPhotoPath: localPhotoPath,
      createdAt: DateTime.now(),
    );
    await _saveLocalReports(
      (await _getLocalReports())
          .map((item) => item.id == withPhoto.id ? withPhoto : item)
          .toList(),
    );
    return _runAutomatedVerification(withPhoto);
  }

  Future<List<HazardReport>> findSimilarReports({
    required HazardType type,
    required double latitude,
    required double longitude,
    Duration window = const Duration(hours: 12),
    double radiusMeters = 250,
  }) async {
    final now = DateTime.now();
    final reports = await getReports(includeCommunityReports: true);
    return reports.where((report) {
      if (!report.isActive || !report.hasCoordinate) return false;
      if (report.type != type) return false;
      if (now.difference(report.createdAt) > window) return false;
      final distance = _distanceMeters(
        MapCoordinate(latitude: latitude, longitude: longitude),
        MapCoordinate(latitude: report.latitude!, longitude: report.longitude!),
      );
      return distance <= radiusMeters;
    }).toList();
  }

  Future<void> deleteReport(String id) async {
    final apiDeleted = await _tryApiDelete(id);
    _storageLabel = apiDeleted ? 'Supabase API' : 'Local device storage';
    final reports = await _getLocalReports();
    await _saveLocalReports(
      reports.where((report) => report.id != id).toList(),
    );
  }

  Future<void> verifyReport(HazardReport report) async {
    await _replaceReport(_verificationService.verifyReport(report));
  }

  Future<void> rejectReport(HazardReport report, String reason) async {
    await _replaceReport(_verificationService.rejectReport(report, reason));
  }

  Future<void> resolveReport(HazardReport report) async {
    await _replaceReport(_verificationService.resolveReport(report));
  }

  Future<List<HazardReport>?> _tryApiRead({
    required bool includeCommunityReports,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      final query = _client.from(_tableName).select();
      final data = includeCommunityReports || userId == null
          ? await query.order('created_at', ascending: false)
          : await query
                .eq('user_id', userId)
                .order('created_at', ascending: false);
      final reports = (data as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(HazardReport.fromJson)
          .toList();
      return Future.wait(reports.map(_withSignedPhotoUrl));
    } catch (error, stackTrace) {
      _log('Supabase read failed: $error');
      debugPrintStack(stackTrace: stackTrace);
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
      final created = await _withSignedPhotoUrl(HazardReport.fromJson(data));
      _log('Supabase insert success: ${created.id}');
      return created;
    } catch (error, stackTrace) {
      _log('Supabase insert failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<bool> _tryApiUpdate(HazardReport report) async {
    try {
      await _client
          .from(_tableName)
          .update(report.toApiUpdateJson())
          .eq('id', report.id);
      _log(
        'Supabase update success: ${report.id} '
        '${hazardReportStatusValue(report.status)} '
        '${report.confidenceScore}/100',
      );
      return true;
    } catch (error, stackTrace) {
      _log('Supabase update failed for ${report.id}: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> _tryApiDelete(String id) async {
    try {
      await _client.from(_tableName).delete().eq('id', id);
      return true;
    } catch (error, stackTrace) {
      _log('Supabase delete failed for $id: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<HazardReport> _replaceReport(HazardReport report) async {
    final apiUpdated = await _tryApiUpdate(report);
    _storageLabel = apiUpdated ? 'Supabase API' : 'Local device storage';
    final reports = await _getLocalReports();
    await _saveLocalReports(
      reports.map((item) => item.id == report.id ? report : item).toList(),
    );
    return report;
  }

  Future<HazardReport> _runAutomatedVerification(HazardReport report) async {
    _log('Starting report verification: ${report.id}');
    try {
      final reports = await _getLocalReports();
      final weatherFuture = report.hasCoordinate
          ? _weatherFor(
              latitude: report.latitude!,
              longitude: report.longitude!,
            )
          : Future<WeatherForecastResponse?>.value();
      final imageFuture = _imageVerificationService.verify(
        hazardType: report.type,
        photoUrl: report.photoUrl,
      );
      final results = await Future.wait<Object?>([weatherFuture, imageFuture]);
      final weather = results[0] as WeatherForecastResponse?;
      final imageVerification = results[1] as HazardImageVerificationResult;
      final verification = await _verificationService.evaluate(
        report,
        context: ReportVerificationContext(
          existingReports: reports,
          reporterId: report.userId ?? _client.auth.currentUser?.id,
          weather: weather,
          imageVerification: imageVerification,
          officialHazardContext: const OfficialHazardContext(
            available: false,
            reason:
                'PAGASA/MGB/GeoRisk machine-readable hazard context is not configured in this build.',
          ),
          isSameUserDuplicate: _hasSameUserDuplicate(
            report,
            reports,
            report.userId ?? _client.auth.currentUser?.id,
          ),
        ),
      );
      _log(
        'final confidence: ${verification.confidenceScore}; '
        'status: ${hazardReportStatusValue(verification.status)}',
      );
      return _replaceReport(
        _verificationService.applyResult(report, verification),
      );
    } catch (error, stackTrace) {
      _log('verification failed for ${report.id}: $error');
      debugPrintStack(stackTrace: stackTrace);
      return _replaceReport(
        report.copyWith(
          status: HazardReportStatus.pending,
          verificationState: HazardVerificationState.failed,
          verificationReason:
              'Automated credibility checks failed temporarily. The report remains pending.',
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<WeatherForecastResponse?> _weatherFor({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final weather = await _weatherService.getForecast(
        latitude: latitude,
        longitude: longitude,
        forecastDays: 1,
      );
      final currentRain =
          weather.current.rainMm + weather.current.precipitationMm;
      final forecastRain = weather.days.isEmpty
          ? 0.0
          : weather.days.first.precipitationMm;
      _log(
        'weather score input: currentRain=$currentRain '
        'forecastRain=$forecastRain',
      );
      return weather;
    } catch (error, stackTrace) {
      _log('weather check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  bool _hasSameUserDuplicate(
    HazardReport report,
    List<HazardReport> reports,
    String? userId,
  ) {
    if (userId == null) return false;
    final now = DateTime.now();
    return reports.any((other) {
      if (other.userId != userId || other.type != report.type) return false;
      if (!other.hasCoordinate || !report.hasCoordinate) return false;
      if (now.difference(other.createdAt) > const Duration(minutes: 10)) {
        return false;
      }
      final distance = _distanceMeters(
        MapCoordinate(latitude: report.latitude!, longitude: report.longitude!),
        MapCoordinate(latitude: other.latitude!, longitude: other.longitude!),
      );
      return distance <= 100;
    });
  }

  Future<void> _tryApiCreateConfirmation(String reportId, String userId) async {
    try {
      await _client.from(_confirmationTableName).insert({
        'report_id': reportId,
        'user_id': userId,
      });
    } catch (_) {
      // Local confirmation storage still prevents repeat confirmations on this device.
    }
  }

  Future<bool> _hasConfirmed(String reportId, String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final confirmations =
        preferences.getStringList(_confirmationStorageKey) ?? const [];
    return confirmations.contains(_confirmationKey(reportId, userId));
  }

  Future<void> _saveLocalConfirmation(String reportId, String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final confirmations = [
      ...(preferences.getStringList(_confirmationStorageKey) ??
          const <String>[]),
    ];
    final key = _confirmationKey(reportId, userId);
    if (!confirmations.contains(key)) confirmations.add(key);
    await preferences.setStringList(_confirmationStorageKey, confirmations);
  }

  String _confirmationKey(String reportId, String userId) =>
      '$reportId::$userId';

  Future<HazardReport> _attachRemotePhoto({
    required HazardReport report,
    required String localPhotoPath,
    required DateTime createdAt,
  }) async {
    final upload = await _uploadPhoto(
      localPhotoPath: localPhotoPath,
      report: report,
      createdAt: createdAt,
    );
    if (upload == null) return report;

    final withPhoto = report.copyWith(
      photoPath: upload.path,
      photoUrl: upload.signedUrl,
      updatedAt: DateTime.now(),
    );
    final updated = await _tryApiUpdate(withPhoto);
    if (!updated) {
      _lastPhotoUploadError =
          'Report submitted, but photo upload reference could not be saved.';
    }
    return withPhoto;
  }

  Future<_PhotoUpload?> _uploadPhoto({
    required String localPhotoPath,
    required HazardReport report,
    required DateTime createdAt,
  }) async {
    _lastPhotoUploadError = null;
    if (localPhotoPath.isEmpty) return null;
    try {
      final file = File(localPhotoPath);
      if (!await file.exists()) {
        _lastPhotoUploadError = 'Selected photo could not be found.';
        return null;
      }
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        _lastPhotoUploadError =
            'Report submitted, but photo upload requires a signed-in user.';
        return null;
      }
      final extension = _safeExtension(localPhotoPath);
      final path =
          '$userId/${report.id}/photo_${createdAt.microsecondsSinceEpoch}.$extension';
      await _client.storage.from(_photoBucket).upload(path, file);
      final signedUrl = await _createSignedPhotoUrl(path);
      _log('photo upload success: $path');
      return _PhotoUpload(path: path, signedUrl: signedUrl);
    } on StorageException catch (error, stackTrace) {
      _log('photo upload failed: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      _lastPhotoUploadError = _photoUploadMessage(error.message);
      return null;
    } catch (error, stackTrace) {
      _log('photo upload failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _lastPhotoUploadError =
          'Report submitted, but photo upload failed. Check your connection and try again.';
      return null;
    }
  }

  Future<HazardReport> _withSignedPhotoUrl(HazardReport report) async {
    final path = report.photoPath;
    if (path == null || path.isEmpty) return report;
    final signedUrl = await _createSignedPhotoUrl(path);
    if (signedUrl == null || signedUrl.isEmpty) return report;
    return report.copyWith(photoUrl: signedUrl);
  }

  Future<String?> _createSignedPhotoUrl(String path) async {
    try {
      return await _client.storage
          .from(_photoBucket)
          .createSignedUrl(path, _signedPhotoUrlSeconds);
    } on StorageException catch (error, stackTrace) {
      _log('signed photo URL failed: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } catch (error, stackTrace) {
      _log('signed photo URL failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  String _safeExtension(String path) {
    final extension = path.split('.').last.toLowerCase();
    if (extension == path || extension.length > 5) return 'jpg';
    return switch (extension) {
      'jpg' || 'jpeg' || 'png' || 'webp' || 'heic' => extension,
      _ => 'jpg',
    };
  }

  String _photoUploadMessage(String detail) {
    final lower = detail.toLowerCase();
    if (lower.contains('bucket') || lower.contains('not found')) {
      return 'Report submitted, but photo upload failed because the hazard-report-photos bucket is missing.';
    }
    if (lower.contains('permission') ||
        lower.contains('policy') ||
        lower.contains('row-level') ||
        lower.contains('unauthorized')) {
      return 'Report submitted, but photo upload was denied by Storage policy.';
    }
    if (lower.contains('mime') || lower.contains('invalid')) {
      return 'Report submitted, but the selected image type is not allowed.';
    }
    return 'Report submitted, but photo upload failed. Check your connection and try again.';
  }

  Future<void> _saveLocalReports(
    List<HazardReport> reports, {
    bool includeCommunityReports = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _localStorageKey(includeCommunityReports: includeCommunityReports),
      reports.map((report) => jsonEncode(report.toJson())).toList(),
    );
  }

  String _localStorageKey({required bool includeCommunityReports}) =>
      includeCommunityReports ? '${_storageKey}_community_cache' : _storageKey;

  double _distanceMeters(MapCoordinate a, MapCoordinate b) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final deltaLat = _radians(b.latitude - a.latitude);
    final deltaLng = _radians(b.longitude - a.longitude);
    final value =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(value), math.sqrt(1 - value));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  void _log(String message) => debugPrint('[Verification] $message');
}

class _PhotoUpload {
  const _PhotoUpload({required this.path, required this.signedUrl});

  final String path;
  final String? signedUrl;
}
