enum HazardType {
  floodedRoad,
  cloggedDrainage,
  blockedWaterway,
  overflowingCanal,
}

class HazardReport {
  const HazardReport({
    required this.type,
    required this.severity,
    required this.location,
    this.description = '',
  });

  final HazardType type;
  final String severity;
  final String location;
  final String description;
}
