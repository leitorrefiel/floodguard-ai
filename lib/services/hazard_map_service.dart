import 'package:flutter/foundation.dart';

import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import 'hazard_report_service.dart';
import 'safety_facility_service.dart';

class HazardMapService {
  HazardMapService({
    HazardReportService? reportService,
    SafetyFacilityService? facilityService,
  }) : _reportService = reportService ?? HazardReportService(),
       _facilityService = facilityService ?? SafetyFacilityService();

  final HazardReportService _reportService;
  final SafetyFacilityService _facilityService;

  Future<HazardMapData> load() async {
    final reports = await _reportService.getReports(
      includeCommunityReports: true,
    );
    final facilities = await _facilityService.loadVerified();
    final mappedReports = <MappedHazardReport>[];

    final visibleReports = reports.where(_isVisibleOnMap).toList();
    debugPrint(
      '[Hazard Map] loaded ${reports.length} reports from '
      '${_reportService.storageLabel}; visible=${visibleReports.length}; '
      'verified facilities=${facilities.length}',
    );

    for (final report in visibleReports.take(20)) {
      debugPrint(
        '[Hazard Map] report id=${report.id} '
        'status=${hazardReportStatusValue(report.status)} '
        'type=${report.type.name} lat=${report.latitude} lng=${report.longitude}',
      );
      if (!report.hasCoordinate) continue;
      mappedReports.add(
        MappedHazardReport(
          report: report,
          coordinate: MapCoordinate(
            latitude: report.latitude!,
            longitude: report.longitude!,
          ),
        ),
      );
    }

    return HazardMapData(
      facilities: facilities,
      reports: mappedReports,
      unmappedReportCount: visibleReports.length - mappedReports.length,
      storageLabel: _reportService.storageLabel,
    );
  }

  bool _isVisibleOnMap(HazardReport report) {
    if (!report.hasCoordinate && report.location.trim().length < 3) {
      return false;
    }
    if (report.expiresAt != null &&
        report.expiresAt!.isBefore(DateTime.now())) {
      return false;
    }
    return report.status == HazardReportStatus.pending ||
        report.status == HazardReportStatus.highConfidence ||
        report.status == HazardReportStatus.verified ||
        report.status == HazardReportStatus.suspicious;
  }
}

String emergencyFacilityTypeLabel(EmergencyFacilityType type) => switch (type) {
  EmergencyFacilityType.evacuation => 'Evacuation Center',
  EmergencyFacilityType.school => 'School',
  EmergencyFacilityType.hospital => 'Hospital',
  EmergencyFacilityType.fireStation => 'Fire Station',
  EmergencyFacilityType.emergencyOffice => 'Emergency Office',
};
