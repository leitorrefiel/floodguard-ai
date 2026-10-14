import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/models/map_hazard.dart';
import 'package:floodguard/services/safety_facility_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled production dataset contains verified references only',
    () async {
      final facilities = await SafetyFacilityService().loadVerified();

      expect(facilities, hasLength(3));
      expect(
        facilities.where(
          (item) => item.type == EmergencyFacilityType.evacuation,
        ),
        isEmpty,
      );
      expect(
        facilities.every(
          (item) =>
              item.sourceUrl.startsWith('https://') &&
              item.coordinateSourceUrl.startsWith('https://') &&
              item.operationalStatus.isNotEmpty,
        ),
        isTrue,
      );
    },
  );

  test('loads only verified reference facilities with source metadata', () {
    final facilities = SafetyFacilityService.decodeVerifiedFacilities(
      jsonEncode({
        'schema_version': 1,
        'facilities': [
          _record(),
          _record(id: 'unverified', verificationStatus: 'unverified'),
        ],
      }),
    );

    expect(facilities, hasLength(1));
    expect(facilities.single.id, 'verified');
    expect(facilities.single.type, EmergencyFacilityType.emergencyOffice);
    expect(facilities.single.sourceUrl, startsWith('https://'));
    expect(facilities.single.operationalStatus, contains('unconfirmed'));
  });

  test('rejects a verified record outside the Baliwag validation area', () {
    expect(
      () => SafetyFacilityService.decodeVerifiedFacilities(
        jsonEncode({
          'schema_version': 1,
          'facilities': [_record(latitude: 0)],
        }),
      ),
      throwsFormatException,
    );
  });

  test('rejects non-HTTPS authority and coordinate sources', () {
    expect(
      () => SafetyFacilityService.decodeVerifiedFacilities(
        jsonEncode({
          'schema_version': 1,
          'facilities': [_record(sourceUrl: 'http://example.test/source')],
        }),
      ),
      throwsFormatException,
    );
  });

  test('evacuation-center layer excludes other safety facilities', () {
    final facilities = [
      _facility(EmergencyFacilityType.fireStation),
      _facility(EmergencyFacilityType.emergencyOffice),
      _facility(EmergencyFacilityType.hospital),
    ];

    expect(SafetyFacilityService.evacuationCenters(facilities), isEmpty);
  });
}

EmergencyFacility _facility(EmergencyFacilityType type) => EmergencyFacility(
  id: type.name,
  name: type.name,
  address: 'Baliwag, Bulacan',
  coordinate: const MapCoordinate(latitude: 14.95, longitude: 120.89),
  type: type,
  sourceName: 'Authority',
  sourceUrl: 'https://example.test/source',
  coordinateSourceName: 'Coordinate source',
  coordinateSourceUrl: 'https://example.test/coordinates',
  verifiedAt: DateTime.utc(2026, 9, 26),
  operationalStatus: 'Opening status unconfirmed',
);

Map<String, dynamic> _record({
  String id = 'verified',
  String verificationStatus = 'verified_reference',
  double latitude = 14.9575455,
  String sourceUrl = 'https://baliwag.gov.ph/government/cdrrmc',
}) => {
  'id': id,
  'name': 'Baliwag CDRRMO',
  'address': 'Pagala, Baliwag, Bulacan',
  'latitude': latitude,
  'longitude': 120.888933,
  'category': 'emergency_office',
  'authority_source_name': 'City Government of Baliwag',
  'authority_source_url': sourceUrl,
  'coordinate_source_name': 'OpenStreetMap contributors',
  'coordinate_source_url': 'https://www.openstreetmap.org/node/11261759986',
  'verification_date': '2026-09-26',
  'verification_status': verificationStatus,
  'operational_status': 'Opening status unconfirmed',
};
