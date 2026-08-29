import 'package:geocoding/geocoding.dart';

import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import 'hazard_report_service.dart';

class HazardMapService {
  HazardMapService({HazardReportService? reportService})
    : _reportService = reportService ?? HazardReportService();

  final HazardReportService _reportService;
  final Map<String, MapCoordinate?> _geocodeCache = {};
  final Geocoding _geocoding = Geocoding();

  static const facilities = [
    EmergencyFacility(
      id: 'facility-baliwag-city-hall',
      name: 'Baliwag City Hall Evacuation Center',
      address: 'Baliwag, Bulacan',
      coordinate: MapCoordinate(latitude: 14.9547, longitude: 120.8969),
      type: EmergencyFacilityType.evacuation,
      recommended: true,
    ),
    EmergencyFacility(
      id: 'facility-baliwag-north-central',
      name: 'Baliwag North Central School',
      address: 'Baliwag, Bulacan',
      coordinate: MapCoordinate(latitude: 14.9636, longitude: 120.8996),
      type: EmergencyFacilityType.school,
    ),
    EmergencyFacility(
      id: 'facility-baliwag-district-hospital',
      name: 'Baliwag District Hospital',
      address: 'Baliwag, Bulacan',
      coordinate: MapCoordinate(latitude: 14.9506, longitude: 120.9018),
      type: EmergencyFacilityType.hospital,
    ),
    EmergencyFacility(
      id: 'facility-baliwag-fire-station',
      name: 'Baliwag Fire Station',
      address: 'Baliwag, Bulacan',
      coordinate: MapCoordinate(latitude: 14.9584, longitude: 120.8912),
      type: EmergencyFacilityType.fireStation,
    ),
  ];

  Future<HazardMapData> load() async {
    final reports = await _reportService.getReports();
    final mappedReports = <MappedHazardReport>[];

    for (final report in reports.take(20)) {
      final coordinate = await _coordinateForReport(report);
      if (coordinate == null) continue;
      mappedReports.add(
        MappedHazardReport(report: report, coordinate: coordinate),
      );
    }

    return HazardMapData(
      facilities: facilities,
      reports: mappedReports,
      unmappedReportCount: reports.length - mappedReports.length,
      storageLabel: _reportService.storageLabel,
    );
  }

  Future<MapCoordinate?> _coordinateForReport(HazardReport report) async {
    final key = report.location.trim().toLowerCase();
    if (key.length < 3) return null;
    if (_geocodeCache.containsKey(key)) return _geocodeCache[key];

    try {
      final locations = await _geocoding
          .locationFromAddress('$key, Philippines')
          .timeout(const Duration(seconds: 5));
      if (locations.isEmpty) {
        _geocodeCache[key] = null;
        return null;
      }
      final location = locations.first;
      final coordinate = MapCoordinate(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      _geocodeCache[key] = coordinate;
      return coordinate;
    } catch (_) {
      _geocodeCache[key] = null;
      return null;
    }
  }
}

String emergencyFacilityTypeLabel(EmergencyFacilityType type) => switch (type) {
  EmergencyFacilityType.evacuation => 'Evacuation Center',
  EmergencyFacilityType.school => 'School',
  EmergencyFacilityType.hospital => 'Hospital',
  EmergencyFacilityType.fireStation => 'Fire Station',
};
