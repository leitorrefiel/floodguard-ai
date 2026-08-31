import 'package:flutter/foundation.dart';

import '../models/hazard_report.dart';
import '../models/map_hazard.dart';

// DEVELOPMENT / VISUAL TEST DATA ONLY.
// DO NOT USE AS REAL FLOOD, HAZARD, OR FACILITY INFORMATION.
const bool useDemoFloodData = kDebugMode;
const bool useDemoHazardData = kDebugMode;
const bool useDemoFacilityData = kDebugMode;

class DemoMapData {
  static final DateTime _timestamp = DateTime(2026, 8, 30, 13, 30);

  static final List<MappedHazardReport> floodReports = [
    _report(
      id: 'demo-flood-moderate-baliwag-road',
      type: HazardType.floodedRoad,
      severity: 'Moderate',
      location: 'DEMO - Baliwag Road near San Roque',
      description: 'TEST DATA - Moderate road flooding visualization.',
      latitude: 14.9819,
      longitude: 120.8818,
    ),
    _report(
      id: 'demo-flood-high-poblacion',
      type: HazardType.floodedRoad,
      severity: 'High',
      location: 'DEMO - Poblacion Baliwag low-lying street',
      description: 'TEST DATA - High flood visualization.',
      latitude: 14.9826,
      longitude: 120.8849,
    ),
    _report(
      id: 'demo-flood-critical-catuliran',
      type: HazardType.floodedRoad,
      severity: 'Critical',
      location: 'DEMO - Catulinan river-adjacent road',
      description: 'TEST DATA - Critical flood visualization.',
      latitude: 14.9802,
      longitude: 120.8837,
    ),
  ];

  static final List<MappedHazardReport> hazardReports = [
    _report(
      id: 'demo-hazard-clogged-drainage',
      type: HazardType.cloggedDrainage,
      severity: 'Moderate',
      location: 'DEMO - Clogged drainage near Barangka',
      description: 'TEST DATA - Drainage hazard marker visualization.',
      latitude: 14.9829,
      longitude: 120.8813,
    ),
    _report(
      id: 'demo-hazard-blocked-waterway',
      type: HazardType.blockedWaterway,
      severity: 'High',
      location: 'DEMO - Blocked waterway near Ulingao',
      description: 'TEST DATA - Blocked waterway hazard visualization.',
      latitude: 14.9834,
      longitude: 120.8835,
    ),
    _report(
      id: 'demo-hazard-overflowing-canal',
      type: HazardType.overflowingCanal,
      severity: 'Critical',
      location: 'DEMO - Overflowing canal near Taal',
      description: 'TEST DATA - Overflowing canal hazard visualization.',
      latitude: 14.9807,
      longitude: 120.8816,
    ),
  ];

  static const List<EmergencyFacility> facilities = [
    EmergencyFacility(
      id: 'demo-facility-evacuation-center',
      name: 'DEMO Evacuation Center',
      address: 'TEST FACILITY - Baliwag demo marker',
      coordinate: MapCoordinate(latitude: 14.9816, longitude: 120.8845),
      type: EmergencyFacilityType.evacuation,
      recommended: true,
    ),
    EmergencyFacility(
      id: 'demo-facility-hospital',
      name: 'DEMO Hospital',
      address: 'TEST FACILITY - Baliwag demo marker',
      coordinate: MapCoordinate(latitude: 14.9823, longitude: 120.8831),
      type: EmergencyFacilityType.hospital,
    ),
    EmergencyFacility(
      id: 'demo-facility-shelter',
      name: 'DEMO Emergency Shelter',
      address: 'TEST FACILITY - Baliwag demo marker',
      coordinate: MapCoordinate(latitude: 14.9804, longitude: 120.8827),
      type: EmergencyFacilityType.school,
    ),
  ];

  static MappedHazardReport _report({
    required String id,
    required HazardType type,
    required String severity,
    required String location,
    required String description,
    required double latitude,
    required double longitude,
  }) {
    final report = HazardReport(
      id: id,
      type: type,
      severity: severity,
      location: location,
      description: description,
      createdAt: _timestamp,
      updatedAt: _timestamp,
    );
    return MappedHazardReport(
      report: report,
      coordinate: MapCoordinate(latitude: latitude, longitude: longitude),
    );
  }
}
