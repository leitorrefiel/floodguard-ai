import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/models/hazard_report.dart';
import 'package:floodguard/services/hazard_image_verification_service.dart';
import 'package:floodguard/services/report_verification_service.dart';
import 'package:floodguard/services/weather_service.dart';

void main() {
  final service = ReportVerificationService();

  HazardReport report({
    String id = 'report-1',
    HazardType type = HazardType.floodedRoad,
    String? userId = 'user-1',
    double latitude = 14.98136,
    double longitude = 120.88310,
    String? photoUrl,
    int confirmations = 0,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return HazardReport(
      id: id,
      type: type,
      severity: 'Moderate',
      location: 'Baliwag, Bulacan',
      description: 'Flooded road',
      latitude: latitude,
      longitude: longitude,
      photoUrl: photoUrl,
      confirmationCount: confirmations,
      userId: userId,
      expiresAt: expiresAt ?? now.add(const Duration(days: 3)),
      createdAt: now,
      updatedAt: now,
    );
  }

  test('one report without supporting evidence stays pending', () async {
    final result = await service.evaluate(
      report(),
      context: const ReportVerificationContext(
        existingReports: [],
        reporterId: 'user-1',
      ),
    );

    expect(result.status, HazardReportStatus.pending);
    expect(result.confidenceScore, 10);
  });

  test(
    'photo and rainfall increase confidence without official verification',
    () async {
      final result = await service.evaluate(
        report(photoUrl: 'https://example.com/photo.jpg'),
        context: ReportVerificationContext(
          existingReports: const [],
          reporterId: 'user-1',
          weather: WeatherForecastResponse(
            current: WeatherSnapshot(
              temperatureCelsius: 26,
              precipitationMm: 2,
              rainMm: 1,
              observedAt: DateTime.now().toIso8601String(),
            ),
            days: [
              WeatherForecastDay(
                date: DateTime.now().toIso8601String(),
                weatherCode: 61,
                maxTemperatureCelsius: 28,
                minTemperatureCelsius: 24,
                precipitationMm: 12,
              ),
            ],
            endpoint: Uri.parse('https://api.open-meteo.com/v1/forecast'),
            jsonSample: '{}',
          ),
        ),
      );

      expect(result.confidenceScore, greaterThan(10));
      expect(result.status, isNot(HazardReportStatus.verified));
    },
  );

  test('relevant image evidence increases confidence', () async {
    final result = await service.evaluate(
      report(photoUrl: 'https://example.com/photo.jpg'),
      context: const ReportVerificationContext(
        existingReports: [],
        reporterId: 'user-1',
        imageVerification: HazardImageVerificationResult(
          matchesReportedHazard: true,
          detectedCategory: 'flooded_road',
          confidence: .86,
          reason: 'Visible water covering a roadway.',
        ),
      ),
    );

    expect(result.confidenceScore, 50);
    expect(result.reason, contains('Photo appears strongly consistent'));
  });

  test('unrelated image keeps report pending instead of deleting it', () async {
    final result = await service.evaluate(
      report(photoUrl: 'https://example.com/unrelated.jpg'),
      context: const ReportVerificationContext(
        existingReports: [],
        reporterId: 'user-1',
        imageVerification: HazardImageVerificationResult(
          matchesReportedHazard: false,
          detectedCategory: 'no_visible_hazard',
          confidence: .82,
          reason: 'No visible hazard.',
        ),
      ),
    );

    expect(result.status, HazardReportStatus.pending);
  });

  test('unavailable image API keeps report pending', () async {
    final result = await service.evaluate(
      report(photoUrl: 'https://example.com/photo.jpg'),
      context: const ReportVerificationContext(
        existingReports: [],
        reporterId: 'user-1',
        imageVerification: HazardImageVerificationResult(
          matchesReportedHazard: false,
          detectedCategory: 'uncertain',
          confidence: 0,
          reason: 'Service unavailable.',
          unavailable: true,
        ),
      ),
    );

    expect(result.status, HazardReportStatus.pending);
    expect(
      result.reason,
      contains('Image verification temporarily unavailable'),
    );
  });

  test(
    'multiple independent matching reports produce high confidence',
    () async {
      final now = DateTime.now();
      final result = await service.evaluate(
        report(createdAt: now),
        context: ReportVerificationContext(
          existingReports: [
            report(id: 'report-2', userId: 'user-2', createdAt: now),
            report(id: 'report-3', userId: 'user-3', createdAt: now),
            report(id: 'report-4', userId: 'user-4', createdAt: now),
          ],
          reporterId: 'user-1',
        ),
      );

      expect(result.status, HazardReportStatus.highConfidence);
    },
  );

  test('same-user rapid duplicate becomes suspicious', () async {
    final now = DateTime.now();
    final result = await service.evaluate(
      report(createdAt: now),
      context: ReportVerificationContext(
        existingReports: [report(id: 'report-2', userId: 'user-1')],
        reporterId: 'user-1',
        isSameUserDuplicate: true,
      ),
    );

    expect(result.status, HazardReportStatus.suspicious);
  });

  test('invalid coordinates are rejected', () async {
    final result = await service.evaluate(
      report(latitude: 120, longitude: 200),
      context: const ReportVerificationContext(
        existingReports: [],
        reporterId: 'user-1',
      ),
    );

    expect(result.status, HazardReportStatus.rejected);
  });

  test('expired reports are marked expired and inactive', () async {
    final expired = report(
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final result = await service.evaluate(
      expired,
      context: const ReportVerificationContext(
        existingReports: [],
        reporterId: 'user-1',
      ),
    );

    expect(result.status, HazardReportStatus.expired);
    expect(service.applyResult(expired, result).isActive, isFalse);
  });

  test('verification state serializes separately from report status', () {
    final pendingRunning = report().copyWith(
      status: HazardReportStatus.pending,
      confidenceScore: 0,
      verificationState: HazardVerificationState.running,
    );

    final json = pendingRunning.toJson();
    expect(json['status'], 'pending');
    expect(json['confidenceScore'], 0);
    expect(json['verificationState'], 'running');

    final restored = HazardReport.fromJson(json);
    expect(restored.status, HazardReportStatus.pending);
    expect(restored.verificationState, HazardVerificationState.running);
  });
}
