import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/models/hazard_report.dart';
import 'package:floodguard/models/map_hazard.dart';
import 'package:floodguard/services/hazard_map_service.dart';
import 'package:floodguard/services/hazard_report_service.dart';
import 'package:floodguard/services/safety_facility_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'keeps verified facilities when remote community reports fail',
    () async {
      final service = HazardMapService(
        reportService: _FailingReportService(),
        facilityService: _FacilityService(),
      );

      final data = await service.load();

      expect(data.facilities, hasLength(1));
      expect(data.reports, isEmpty);
      expect(data.communityReportsAvailable, isFalse);
      expect(data.storageLabel, 'Remote community reports unavailable');
      expect(
        data.reportDataError,
        contains('Community reports are unavailable'),
      );
    },
  );

  test(
    'omits expired reports and reports without usable coordinates',
    () async {
      final now = DateTime.now();
      final service = HazardMapService(
        reportService: _ReportService([
          _report(
            id: 'expired',
            latitude: 14.95,
            longitude: 120.89,
            expiresAt: now.subtract(const Duration(minutes: 1)),
          ),
          _report(id: 'unmapped', latitude: null, longitude: null),
          _report(id: 'active', latitude: 14.96, longitude: 120.90),
        ]),
        facilityService: _EmptyFacilityService(),
      );

      final data = await service.load();

      expect(data.reports.map((item) => item.report.id), ['active']);
      expect(data.unmappedReportCount, 1);
    },
  );
}

class _ReportService extends HazardReportService {
  _ReportService(this.reports)
    : super(client: SupabaseClient('https://example.supabase.co', 'test-key'));

  final List<HazardReport> reports;

  @override
  Future<List<HazardReport>> getReports({
    bool includeCommunityReports = false,
  }) async => reports;
}

class _EmptyFacilityService extends SafetyFacilityService {
  @override
  Future<List<EmergencyFacility>> loadVerified() async => const [];
}

HazardReport _report({
  required String id,
  required double? latitude,
  required double? longitude,
  DateTime? expiresAt,
}) {
  final now = DateTime.now();
  return HazardReport(
    id: id,
    type: HazardType.floodedRoad,
    severity: 'Moderate',
    location: 'Baliwag, Bulacan',
    latitude: latitude,
    longitude: longitude,
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
    createdAt: now,
    updatedAt: now,
  );
}

class _FailingReportService extends HazardReportService {
  _FailingReportService()
    : super(client: SupabaseClient('https://example.supabase.co', 'test-key'));

  @override
  Future<List<HazardReport>> getReports({
    bool includeCommunityReports = false,
  }) async {
    throw const SupabaseRemoteRequiredException('read');
  }
}

class _FacilityService extends SafetyFacilityService {
  @override
  Future<List<EmergencyFacility>> loadVerified() async => [
    EmergencyFacility(
      id: 'verified-office',
      name: 'Verified Emergency Office',
      address: 'Baliwag, Bulacan',
      coordinate: const MapCoordinate(
        latitude: 14.9575455,
        longitude: 120.888933,
      ),
      type: EmergencyFacilityType.emergencyOffice,
      sourceName: 'Official source',
      sourceUrl: 'https://example.gov.ph/facility',
      coordinateSourceName: 'Coordinate source',
      coordinateSourceUrl: 'https://www.openstreetmap.org/node/1',
      verifiedAt: DateTime(2026, 10, 14),
      operationalStatus: 'Opening status unconfirmed',
    ),
  ];
}
