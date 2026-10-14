import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/map_hazard.dart';

class SafetyFacilityService {
  SafetyFacilityService({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const assetPath = 'assets/data/verified_safety_facilities.json';

  static List<EmergencyFacility> evacuationCenters(
    Iterable<EmergencyFacility> facilities,
  ) => facilities
      .where((facility) => facility.type == EmergencyFacilityType.evacuation)
      .toList(growable: false);

  final AssetBundle _bundle;

  Future<List<EmergencyFacility>> loadVerified() async {
    final raw = await _bundle.loadString(assetPath);
    return decodeVerifiedFacilities(raw);
  }

  static List<EmergencyFacility> decodeVerifiedFacilities(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['schema_version'] != 1) {
      throw const FormatException('Unsupported safety-facility dataset.');
    }
    final records = decoded['facilities'];
    if (records is! List) {
      throw const FormatException('Safety-facility records are missing.');
    }

    return records
        .whereType<Map<String, dynamic>>()
        .where(
          (record) => record['verification_status'] == 'verified_reference',
        )
        .map(_parseVerifiedFacility)
        .toList(growable: false);
  }

  static EmergencyFacility _parseVerifiedFacility(Map<String, dynamic> record) {
    final id = _requiredString(record, 'id');
    final name = _requiredString(record, 'name');
    final address = _requiredString(record, 'address');
    final latitude = _requiredNumber(record, 'latitude');
    final longitude = _requiredNumber(record, 'longitude');
    final sourceUrl = _requiredHttpsUrl(record, 'authority_source_url');
    final coordinateSourceUrl = _requiredHttpsUrl(
      record,
      'coordinate_source_url',
    );
    final verifiedAt = DateTime.tryParse(
      _requiredString(record, 'verification_date'),
    );
    if (verifiedAt == null) {
      throw FormatException('Invalid verification date for $id.');
    }
    if (latitude < 14.7 ||
        latitude > 15.2 ||
        longitude < 120.7 ||
        longitude > 121.1) {
      throw FormatException(
        'Facility $id is outside the Baliwag validation area.',
      );
    }

    return EmergencyFacility(
      id: id,
      name: name,
      address: address,
      coordinate: MapCoordinate(latitude: latitude, longitude: longitude),
      type: _parseType(_requiredString(record, 'category')),
      sourceName: _requiredString(record, 'authority_source_name'),
      sourceUrl: sourceUrl,
      coordinateSourceName: _requiredString(record, 'coordinate_source_name'),
      coordinateSourceUrl: coordinateSourceUrl,
      verifiedAt: verifiedAt,
      operationalStatus: _requiredString(record, 'operational_status'),
    );
  }

  static EmergencyFacilityType _parseType(String value) => switch (value) {
    'evacuation_center' => EmergencyFacilityType.evacuation,
    'school' => EmergencyFacilityType.school,
    'hospital' => EmergencyFacilityType.hospital,
    'fire_station' => EmergencyFacilityType.fireStation,
    'emergency_office' => EmergencyFacilityType.emergencyOffice,
    _ => throw FormatException('Unsupported facility category: $value'),
  };

  static String _requiredString(Map<String, dynamic> record, String key) {
    final value = record[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw FormatException('Facility field $key is required.');
    }
    return value;
  }

  static double _requiredNumber(Map<String, dynamic> record, String key) {
    final value = record[key];
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Facility field $key must be numeric.');
  }

  static String _requiredHttpsUrl(Map<String, dynamic> record, String key) {
    final value = _requiredString(record, key);
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw FormatException('Facility field $key must be an HTTPS URL.');
    }
    return value;
  }
}
