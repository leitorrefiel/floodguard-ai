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
