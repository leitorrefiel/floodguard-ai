import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import 'hazard_image_verification_service.dart';
import 'weather_service.dart';

class ReportVerificationContext {
  const ReportVerificationContext({
    required this.existingReports,
    required this.reporterId,
    this.weather,
    this.imageVerification,
    this.officialHazardContext,
    this.isSameUserDuplicate = false,
  });

  final List<HazardReport> existingReports;
  final String? reporterId;
  final WeatherForecastResponse? weather;
  final HazardImageVerificationResult? imageVerification;
  final OfficialHazardContext? officialHazardContext;
  final bool isSameUserDuplicate;
}

class OfficialHazardContext {
  const OfficialHazardContext({
    required this.available,
    this.highFloodSusceptibility = false,
    this.reason = 'Official hazard context is not configured.',
  });

  final bool available;
  final bool highFloodSusceptibility;
  final String reason;

  Map<String, dynamic> toJson() => {
    'available': available,
    'high_flood_susceptibility': highFloodSusceptibility,
    'reason': reason,
  };
}

class ReportVerificationResult {
  const ReportVerificationResult({
    required this.status,
    required this.confidenceScore,
    required this.reason,
    required this.evidence,
    required this.verificationState,
    required this.lastVerifiedAt,
  });

  final HazardReportStatus status;
  final int confidenceScore;
  final String reason;
  final Map<String, dynamic> evidence;
  final HazardVerificationState verificationState;
  final DateTime? lastVerifiedAt;
}

class ReportVerificationService {
  static const int validLocationPoints = 10;
  static const int photoEvidencePoints = 15;
  static const int strongImageMatchPoints = 25;
  static const int moderateImageMatchPoints = 15;
  static const int imageMismatchPenalty = 10;
  static const int moderateRainPoints = 8;
  static const int heavyRainPoints = 15;
  static const int officialFloodSusceptibilityPoints = 10;
  static const int independentNearbyReportPoints = 20;
  static const int independentConfirmationPoints = 10;
  static const int sameUserDuplicatePenalty = 30;

  static const double nearbyRadiusMeters = 250;
  static const Duration nearbyWindow = Duration(hours: 3);

  Future<ReportVerificationResult> evaluate(
    HazardReport report, {
    required ReportVerificationContext context,
  }) async {
    final now = DateTime.now();
    final signals = <String>[];
    var score = 0;

    if (!_hasValidCoordinates(report)) {
      return const ReportVerificationResult(
        status: HazardReportStatus.rejected,
        confidenceScore: 0,
        reason: 'Rejected because the report has invalid map coordinates.',
        evidence: {
          'location': {
            'valid': false,
            'reason': 'Invalid or impossible latitude/longitude.',
          },
        },
        verificationState: HazardVerificationState.completed,
        lastVerifiedAt: null,
      );
    }

    if (report.expiresAt != null && report.expiresAt!.isBefore(now)) {
      return ReportVerificationResult(
        status: HazardReportStatus.expired,
        confidenceScore: report.confidenceScore,
        reason: 'Expired because the report is outside its active window.',
        evidence: report.verificationEvidence,
        verificationState: HazardVerificationState.completed,
        lastVerifiedAt: now,
      );
    }

    final evidence = <String, dynamic>{};
    score += validLocationPoints;
    _log('location score: +$validLocationPoints');
    signals.add('Valid GPS/map location');
    evidence['location'] = {
      'valid': true,
      'latitude': report.latitude,
      'longitude': report.longitude,
      'supported_area_checked': false,
    };

    final hasPhotoEvidence =
        (report.photoUrl ?? '').trim().isNotEmpty ||
        (report.photoPath ?? '').trim().isNotEmpty;
    if (hasPhotoEvidence) {
      score += photoEvidencePoints;
      _log('photo score: +$photoEvidencePoints');
      signals.add('Photo evidence provided');
    } else {
      _log('photo score: +0');
    }

    final image = context.imageVerification;
    if (image != null) {
      evidence['image'] = image.toJson();
      if (image.unavailable) {
        _log('AI score: +0 unavailable');
        signals.add('Image verification temporarily unavailable');
      } else if (image.matchesReportedHazard && image.confidence >= .75) {
        score += strongImageMatchPoints;
        _log('AI score: +$strongImageMatchPoints');
        signals.add(
          'Photo appears strongly consistent with the reported hazard',
        );
      } else if (image.matchesReportedHazard && image.confidence >= .45) {
        score += moderateImageMatchPoints;
        _log('AI score: +$moderateImageMatchPoints');
        signals.add(
          'Photo appears moderately consistent with the reported hazard',
        );
      } else if (image.detectedCategory == 'no_visible_hazard') {
        score -= imageMismatchPenalty;
        _log('AI score: -$imageMismatchPenalty');
        signals.add('Image check did not find a visible matching hazard');
      } else {
        _log('AI score: +0 uncertain');
        signals.add('Image verification was uncertain');
      }
    } else {
      _log('AI score: +0 unavailable');
      evidence['image'] = {
        'unavailable': true,
        'reason': 'No image verification result was available.',
      };
    }

    final weather = context.weather;
    if (weather != null) {
      final currentRain =
          weather.current.rainMm + weather.current.precipitationMm;
      final forecastRain = weather.days.isEmpty
          ? 0
          : weather.days.first.precipitationMm;
      final rainRelevant =
          report.type == HazardType.floodedRoad ||
          report.type == HazardType.overflowingCanal;
      var weatherSupport = 'none';
      if (rainRelevant && currentRain >= 7) {
        score += heavyRainPoints;
        _log('weather score: +$heavyRainPoints');
        weatherSupport = 'heavy';
        signals.add('Heavy rainfall detected near report location');
      } else if (rainRelevant && currentRain >= 2) {
        score += moderateRainPoints;
        _log('weather score: +$moderateRainPoints');
        weatherSupport = 'moderate';
        signals.add('Moderate rainfall detected near report location');
      } else {
        _log('weather score: +0');
      }
      if (rainRelevant && forecastRain >= 10) {
        score += moderateRainPoints;
        _log('forecast weather score: +$moderateRainPoints');
        signals.add('Forecast rainfall may support flood conditions');
      } else {
        _log('forecast weather score: +0');
      }
      evidence['weather'] = {
        'available': true,
        'rain_relevant': rainRelevant,
        'current_rain_mm': currentRain,
        'forecast_rain_mm': forecastRain,
        'support': weatherSupport,
      };
    } else {
      evidence['weather'] = {
        'available': false,
        'reason': 'Weather check temporarily unavailable.',
      };
      _log('weather score: +0 unavailable');
      signals.add('Some verification checks are temporarily unavailable');
    }

    final official = context.officialHazardContext;
    if (official != null) {
      evidence['official_hazard_context'] = official.toJson();
      if (official.available && official.highFloodSusceptibility) {
        score += officialFloodSusceptibilityPoints;
        _log(
          'official hazard context score: +$officialFloodSusceptibilityPoints',
        );
        signals.add('Location is in a flood-susceptible area');
      } else if (!official.available) {
        _log('official hazard context score: +0 unavailable');
        signals.add('Official hazard context is not configured');
      } else {
        _log('official hazard context score: +0');
      }
    } else {
      evidence['official_hazard_context'] = const {
        'available': false,
        'reason': 'No official hazard context service is configured.',
      };
    }

    final independentMatches = _independentNearbyMatches(report, context);
    evidence['nearby_reports'] = {
      'count': independentMatches.length,
      'radius_meters': nearbyRadiusMeters,
      'window_hours': nearbyWindow.inHours,
    };
    if (independentMatches.isNotEmpty) {
      final nearbyScore =
          independentNearbyReportPoints * independentMatches.length;
      score += nearbyScore;
      _log('nearby report score: +$nearbyScore');
      signals.add(
        '${independentMatches.length} independent nearby matching report${independentMatches.length == 1 ? '' : 's'}',
      );
    } else {
      _log('nearby report score: +0');
    }

    final independentConfirmations = math.min(report.confirmationCount, 5);
    evidence['community_confirmations'] = {
      'count': report.confirmationCount,
      'counted': independentConfirmations,
    };
    if (independentConfirmations > 0) {
      final confirmationScore =
          independentConfirmationPoints * independentConfirmations;
      score += confirmationScore;
      _log('community confirmation score: +$confirmationScore');
      signals.add(
        '$independentConfirmations community confirmation${independentConfirmations == 1 ? '' : 's'}',
      );
    } else {
      _log('community confirmation score: +0');
    }

    evidence['duplicate'] = {'same_user_rapid': context.isSameUserDuplicate};
    if (context.isSameUserDuplicate) {
      score -= sameUserDuplicatePenalty;
      _log('duplicate score: -$sameUserDuplicatePenalty');
      signals.add('Possible duplicate from the same reporter');
    } else {
      _log('duplicate score: +0');
    }

    score = score.clamp(0, 100);
    final status = _statusFor(score, duplicate: context.isSameUserDuplicate);
    final statusText = hazardReportStatusLabel(status);
    final reason = signals.isEmpty
        ? '$statusText. No supporting verification signals are currently available.'
        : '$statusText. Supporting evidence: ${signals.join(', ')}.';

    return ReportVerificationResult(
      status: status,
      confidenceScore: score,
      reason: reason,
      evidence: evidence,
      verificationState: HazardVerificationState.completed,
      lastVerifiedAt: now,
    );
  }

  HazardReport applyResult(
    HazardReport report,
    ReportVerificationResult result,
  ) => report.copyWith(
    status: result.status,
    isVerified: result.status == HazardReportStatus.verified,
    confidenceScore: result.confidenceScore,
    verificationState: result.verificationState,
    verificationReason: result.reason,
    verificationEvidence: result.evidence,
    lastVerifiedAt: result.lastVerifiedAt,
    updatedAt: DateTime.now(),
  );

  HazardReport verifyReport(HazardReport report) => report.copyWith(
    status: HazardReportStatus.verified,
    isVerified: true,
    confidenceScore: 100,
    verificationReason: 'Verified by an authorized review process.',
    lastVerifiedAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  HazardReport rejectReport(HazardReport report, String reason) =>
      report.copyWith(
        status: HazardReportStatus.rejected,
        isVerified: false,
        verificationReason: reason,
        lastVerifiedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  HazardReport resolveReport(HazardReport report) => report.copyWith(
    status: HazardReportStatus.resolved,
    isVerified: false,
    verificationReason: 'Marked resolved. Retained in report history.',
    lastVerifiedAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  HazardReportStatus _statusFor(int score, {required bool duplicate}) {
    if (duplicate && score < 35) return HazardReportStatus.suspicious;
    if (score >= 70) return HazardReportStatus.highConfidence;
    return HazardReportStatus.pending;
  }

  bool _hasValidCoordinates(HazardReport report) {
    final latitude = report.latitude;
    final longitude = report.longitude;
    if (latitude == null || longitude == null) return false;
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  List<HazardReport> _independentNearbyMatches(
    HazardReport report,
    ReportVerificationContext context,
  ) {
    final now = DateTime.now();
    return context.existingReports.where((other) {
      if (other.id == report.id) return false;
      if (!other.isActive || !other.hasCoordinate) return false;
      if (other.type != report.type) return false;
      if (now.difference(other.createdAt) > nearbyWindow) return false;
      if (context.reporterId != null && other.userId == context.reporterId) {
        return false;
      }
      final distance = _distanceMeters(
        MapCoordinate(latitude: report.latitude!, longitude: report.longitude!),
        MapCoordinate(latitude: other.latitude!, longitude: other.longitude!),
      );
      return distance <= nearbyRadiusMeters;
    }).toList();
  }

  double _distanceMeters(MapCoordinate a, MapCoordinate b) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final deltaLat = _radians(b.latitude - a.latitude);
    final deltaLng = _radians(b.longitude - a.longitude);
    final value =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(value), math.sqrt(1 - value));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  void _log(String message) => debugPrint('[Verification] $message');
}
