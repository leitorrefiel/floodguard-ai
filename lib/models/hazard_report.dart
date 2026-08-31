enum HazardType {
  floodedRoad,
  cloggedDrainage,
  blockedWaterway,
  overflowingCanal,
  roadObstruction,
  damagedDrainage,
  other,
}

enum HazardReportStatus {
  pending,
  highConfidence,
  verified,
  suspicious,
  rejected,
  resolved,
  expired,
}

enum HazardVerificationState { notStarted, running, completed, failed }

class HazardReport {
  const HazardReport({
    required this.id,
    required this.type,
    required this.severity,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.latitude,
    this.longitude,
    this.photoPath,
    this.photoUrl,
    this.status = HazardReportStatus.pending,
    this.isVerified = false,
    this.confidenceScore = 0,
    this.verificationState = HazardVerificationState.notStarted,
    this.verificationReason = 'Pending verification.',
    this.verificationEvidence = const {},
    this.confirmationCount = 0,
    this.lastVerifiedAt,
    this.expiresAt,
    this.otherHazardType,
    this.userId,
    this.source = 'FloodGuard Community Report',
  });

  factory HazardReport.fromJson(Map<String, dynamic> json) {
    final createdAtValue =
        json['createdAt'] as String? ?? json['created_at'] as String;
    final updatedAtValue =
        json['updatedAt'] as String? ??
        json['updated_at'] as String? ??
        createdAtValue;
    final parsedVerificationState = _verificationStateFromValue(
      json['verificationState'] as String? ??
          json['verification_state'] as String?,
    );
    final parsedConfidenceScore =
        json['confidenceScore'] as int? ??
        json['confidence_score'] as int? ??
        0;
    final parsedStatus = _normalizedStatus(
      _statusFromValue(json['status'] as String?),
      confidenceScore: parsedConfidenceScore,
      verificationState: parsedVerificationState,
    );

    return HazardReport(
      id: json['id'].toString(),
      type: HazardType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => HazardType.floodedRoad,
      ),
      severity: json['severity'] as String? ?? 'Moderate',
      location: json['location'] as String? ?? '',
      description: json['description'] as String? ?? '',
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      photoPath: json['photoPath'] as String? ?? json['photo_path'] as String?,
      photoUrl: json['photoUrl'] as String? ?? json['photo_url'] as String?,
      status: parsedStatus,
      isVerified:
          json['isVerified'] as bool? ?? json['is_verified'] as bool? ?? false,
      confidenceScore: parsedConfidenceScore,
      verificationState: parsedVerificationState,
      verificationReason:
          json['verificationReason'] as String? ??
          json['verification_reason'] as String? ??
          'Pending verification.',
      verificationEvidence: _asMap(
        json['verificationEvidence'] ?? json['verification_evidence'],
      ),
      confirmationCount:
          json['confirmationCount'] as int? ??
          json['confirmation_count'] as int? ??
          0,
      lastVerifiedAt: _asDateTime(
        json['lastVerifiedAt'] ?? json['last_verified_at'],
      ),
      expiresAt: _asDateTime(json['expiresAt'] ?? json['expires_at']),
      otherHazardType:
          json['otherHazardType'] as String? ??
          json['other_hazard_type'] as String?,
      userId: json['userId'] as String? ?? json['user_id'] as String?,
      source: json['source'] as String? ?? 'FloodGuard Community Report',
      createdAt: DateTime.parse(createdAtValue).toLocal(),
      updatedAt: DateTime.parse(updatedAtValue).toLocal(),
    );
  }

  final String id;
  final HazardType type;
  final String severity;
  final String location;
  final String description;
  final double? latitude;
  final double? longitude;
  final String? photoPath;
  final String? photoUrl;
  final HazardReportStatus status;
  final bool isVerified;
  final int confidenceScore;
  final HazardVerificationState verificationState;
  final String verificationReason;
  final Map<String, dynamic> verificationEvidence;
  final int confirmationCount;
  final DateTime? lastVerifiedAt;
  final DateTime? expiresAt;
  final String? otherHazardType;
  final String? userId;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasCoordinate => latitude != null && longitude != null;
  bool get isActive =>
      (expiresAt == null || expiresAt!.isAfter(DateTime.now())) &&
      (status == HazardReportStatus.pending ||
          status == HazardReportStatus.highConfidence ||
          status == HazardReportStatus.verified ||
          status == HazardReportStatus.suspicious);
  bool get isPending => status == HazardReportStatus.pending;
  bool get contributesToRisk =>
      status == HazardReportStatus.highConfidence ||
      status == HazardReportStatus.verified;

  String get displayType =>
      type == HazardType.other && (otherHazardType?.trim().isNotEmpty ?? false)
      ? otherHazardType!.trim()
      : hazardTypeLabel(type);

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'severity': severity,
    'location': location,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'photoPath': photoPath,
    'photoUrl': photoUrl,
    'status': hazardReportStatusValue(status),
    'isVerified': isVerified,
    'confidenceScore': confidenceScore,
    'verificationState': hazardVerificationStateValue(verificationState),
    'verificationReason': verificationReason,
    'verificationEvidence': verificationEvidence,
    'confirmationCount': confirmationCount,
    'lastVerifiedAt': lastVerifiedAt?.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'otherHazardType': otherHazardType,
    'userId': userId,
    'source': source,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toApiInsertJson({String? userId}) => {
    'user_id': userId,
    'type': type.name,
    'severity': severity,
    'location': location,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'photo_path': photoPath,
    'photo_url': _persistablePhotoUrl,
    'status': hazardReportStatusValue(status),
    'is_verified': isVerified,
    'confidence_score': confidenceScore,
    'verification_state': hazardVerificationStateValue(verificationState),
    'verification_reason': verificationReason,
    'verification_evidence': verificationEvidence,
    'ai_image_score': _aiImageScore,
    'weather_support': _weatherSupport,
    'hazard_context_support': _hazardContextSupport,
    'nearby_report_count': _nearbyReportCount,
    'confirmation_count': confirmationCount,
    'last_verified_at': lastVerifiedAt?.toUtc().toIso8601String(),
    'verification_updated_at': lastVerifiedAt?.toUtc().toIso8601String(),
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'other_hazard_type': otherHazardType,
    'source': source,
  };

  Map<String, dynamic> toApiUpdateJson() => {
    'type': type.name,
    'severity': severity,
    'location': location,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'photo_path': photoPath,
    'photo_url': _persistablePhotoUrl,
    'status': hazardReportStatusValue(status),
    'is_verified': isVerified,
    'confidence_score': confidenceScore,
    'verification_state': hazardVerificationStateValue(verificationState),
    'verification_reason': verificationReason,
    'verification_evidence': verificationEvidence,
    'ai_image_score': _aiImageScore,
    'weather_support': _weatherSupport,
    'hazard_context_support': _hazardContextSupport,
    'nearby_report_count': _nearbyReportCount,
    'confirmation_count': confirmationCount,
    'last_verified_at': lastVerifiedAt?.toUtc().toIso8601String(),
    'verification_updated_at': lastVerifiedAt?.toUtc().toIso8601String(),
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'other_hazard_type': otherHazardType,
    'source': source,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  HazardReport copyWith({
    String? id,
    HazardType? type,
    String? severity,
    String? location,
    String? description,
    double? latitude,
    double? longitude,
    String? photoPath,
    String? photoUrl,
    HazardReportStatus? status,
    bool? isVerified,
    int? confidenceScore,
    HazardVerificationState? verificationState,
    String? verificationReason,
    Map<String, dynamic>? verificationEvidence,
    int? confirmationCount,
    DateTime? lastVerifiedAt,
    DateTime? expiresAt,
    String? otherHazardType,
    String? userId,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => HazardReport(
    id: id ?? this.id,
    type: type ?? this.type,
    severity: severity ?? this.severity,
    location: location ?? this.location,
    description: description ?? this.description,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    photoPath: photoPath ?? this.photoPath,
    photoUrl: photoUrl ?? this.photoUrl,
    status: status ?? this.status,
    isVerified: isVerified ?? this.isVerified,
    confidenceScore: confidenceScore ?? this.confidenceScore,
    verificationState: verificationState ?? this.verificationState,
    verificationReason: verificationReason ?? this.verificationReason,
    verificationEvidence: verificationEvidence ?? this.verificationEvidence,
    confirmationCount: confirmationCount ?? this.confirmationCount,
    lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    otherHazardType: otherHazardType ?? this.otherHazardType,
    userId: userId ?? this.userId,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  String? get _persistablePhotoUrl {
    if ((photoPath ?? '').isNotEmpty) return null;
    final value = photoUrl;
    if (value == null || value.isEmpty || !value.startsWith('http')) {
      return null;
    }
    return value;
  }

  double? get _aiImageScore {
    final image = verificationEvidence['image'];
    if (image is! Map) return null;
    final confidence = image['confidence'];
    if (confidence is num) return confidence.toDouble();
    return null;
  }

  bool get _weatherSupport {
    final weather = verificationEvidence['weather'];
    if (weather is! Map) return false;
    return weather['support'] == 'moderate' || weather['support'] == 'heavy';
  }

  bool get _hazardContextSupport {
    final context = verificationEvidence['official_hazard_context'];
    if (context is! Map) return false;
    return context['high_flood_susceptibility'] == true;
  }

  int get _nearbyReportCount {
    final nearby = verificationEvidence['nearby_reports'];
    if (nearby is! Map) return 0;
    final count = nearby['count'];
    if (count is num) return count.toInt();
    return 0;
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? _asDateTime(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

HazardReportStatus _statusFromValue(String? value) => switch (value) {
  'high_confidence' || 'highConfidence' => HazardReportStatus.highConfidence,
  'verified' => HazardReportStatus.verified,
  'suspicious' => HazardReportStatus.suspicious,
  'rejected' => HazardReportStatus.rejected,
  'resolved' => HazardReportStatus.resolved,
  'expired' => HazardReportStatus.expired,
  _ => HazardReportStatus.pending,
};

HazardReportStatus _normalizedStatus(
  HazardReportStatus status, {
  required int confidenceScore,
  required HazardVerificationState verificationState,
}) {
  if (status == HazardReportStatus.suspicious &&
      confidenceScore == 0 &&
      verificationState != HazardVerificationState.completed) {
    return HazardReportStatus.pending;
  }
  return status;
}

String hazardReportStatusValue(HazardReportStatus status) => switch (status) {
  HazardReportStatus.pending => 'pending',
  HazardReportStatus.highConfidence => 'high_confidence',
  HazardReportStatus.verified => 'verified',
  HazardReportStatus.suspicious => 'suspicious',
  HazardReportStatus.rejected => 'rejected',
  HazardReportStatus.resolved => 'resolved',
  HazardReportStatus.expired => 'expired',
};

HazardVerificationState _verificationStateFromValue(String? value) =>
    switch (value) {
      'running' => HazardVerificationState.running,
      'completed' => HazardVerificationState.completed,
      'failed' => HazardVerificationState.failed,
      _ => HazardVerificationState.notStarted,
    };

String hazardVerificationStateValue(HazardVerificationState state) =>
    switch (state) {
      HazardVerificationState.notStarted => 'not_started',
      HazardVerificationState.running => 'running',
      HazardVerificationState.completed => 'completed',
      HazardVerificationState.failed => 'failed',
    };

String hazardVerificationStateLabel(HazardVerificationState state) =>
    switch (state) {
      HazardVerificationState.notStarted => 'Not started',
      HazardVerificationState.running => 'Verification in progress',
      HazardVerificationState.completed => 'Verification completed',
      HazardVerificationState.failed => 'Verification failed',
    };

String hazardTypeLabel(HazardType type) => switch (type) {
  HazardType.floodedRoad => 'Flooded Road',
  HazardType.cloggedDrainage => 'Clogged Drainage',
  HazardType.blockedWaterway => 'Blocked Waterway',
  HazardType.overflowingCanal => 'Overflowing Canal',
  HazardType.roadObstruction => 'Road Obstruction',
  HazardType.damagedDrainage => 'Damaged Drainage',
  HazardType.other => 'Other',
};

String hazardReportStatusLabel(HazardReportStatus status) => switch (status) {
  HazardReportStatus.pending => 'Pending',
  HazardReportStatus.highConfidence => 'High Confidence',
  HazardReportStatus.verified => 'Verified',
  HazardReportStatus.suspicious => 'Suspicious',
  HazardReportStatus.rejected => 'Rejected',
  HazardReportStatus.resolved => 'Resolved',
  HazardReportStatus.expired => 'Expired',
};
