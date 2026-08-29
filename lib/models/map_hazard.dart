import 'hazard_report.dart';

class MapCoordinate {
  const MapCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

enum EmergencyFacilityType { evacuation, school, hospital, fireStation }

class EmergencyFacility {
  const EmergencyFacility({
    required this.id,
    required this.name,
    required this.address,
    required this.coordinate,
    required this.type,
    this.recommended = false,
  });

  final String id;
  final String name;
  final String address;
  final MapCoordinate coordinate;
  final EmergencyFacilityType type;
  final bool recommended;
}

class MappedHazardReport {
  const MappedHazardReport({required this.report, required this.coordinate});

  final HazardReport report;
  final MapCoordinate coordinate;
}

class HazardMapData {
  const HazardMapData({
    required this.facilities,
    required this.reports,
    required this.unmappedReportCount,
    required this.storageLabel,
  });

  final List<EmergencyFacility> facilities;
  final List<MappedHazardReport> reports;
  final int unmappedReportCount;
  final String storageLabel;
}
