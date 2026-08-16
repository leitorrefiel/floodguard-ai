enum HazardType {
  floodedRoad,
  cloggedDrainage,
  blockedWaterway,
  overflowingCanal,
}

class HazardReport {
  const HazardReport({
    required this.id,
    required this.type,
    required this.severity,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
  });

  factory HazardReport.fromJson(Map<String, dynamic> json) => HazardReport(
    id: json['id'] as String,
    type: HazardType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => HazardType.floodedRoad,
    ),
    severity: json['severity'] as String? ?? 'Moderate',
    location: json['location'] as String? ?? '',
    description: json['description'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
  );

  final String id;
  final HazardType type;
  final String severity;
  final String location;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'severity': severity,
    'location': location,
    'description': description,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  HazardReport copyWith({
    String? id,
    HazardType? type,
    String? severity,
    String? location,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => HazardReport(
    id: id ?? this.id,
    type: type ?? this.type,
    severity: severity ?? this.severity,
    location: location ?? this.location,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

String hazardTypeLabel(HazardType type) => switch (type) {
  HazardType.floodedRoad => 'Flooded Road',
  HazardType.cloggedDrainage => 'Clogged Drainage',
  HazardType.blockedWaterway => 'Blocked Waterway',
  HazardType.overflowingCanal => 'Overflowing Canal',
};
