import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hazard_report.dart';

class HazardImageVerificationResult {
  const HazardImageVerificationResult({
    required this.matchesReportedHazard,
    required this.detectedCategory,
    required this.confidence,
    required this.reason,
    this.unavailable = false,
  });

  factory HazardImageVerificationResult.fromJson(Map<String, dynamic> json) =>
      HazardImageVerificationResult(
        matchesReportedHazard:
            json['matches_reported_hazard'] as bool? ?? false,
        detectedCategory: json['detected_category'] as String? ?? 'uncertain',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        reason: json['reason'] as String? ?? 'No image reason returned.',
      );

  final bool matchesReportedHazard;
  final String detectedCategory;
  final double confidence;
  final String reason;
  final bool unavailable;

  Map<String, dynamic> toJson() => {
    'matches_reported_hazard': matchesReportedHazard,
    'detected_category': detectedCategory,
    'confidence': confidence,
    'reason': reason,
    'unavailable': unavailable,
  };
}

class HazardImageVerificationService {
  HazardImageVerificationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<HazardImageVerificationResult> verify({
    required HazardType hazardType,
    required String? photoUrl,
  }) async {
    if (photoUrl == null || photoUrl.isEmpty || !photoUrl.startsWith('http')) {
      _log('AI result: unavailable, no public photo URL');
      return const HazardImageVerificationResult(
        matchesReportedHazard: false,
        detectedCategory: 'uncertain',
        confidence: 0,
        reason:
            'Image verification unavailable because no public uploaded photo URL is available.',
        unavailable: true,
      );
    }

    try {
      final response = await _client.functions
          .invoke(
            'verify-hazard-photo',
            body: {
              'photo_url': photoUrl,
              'reported_category': hazardTypeVerificationValue(hazardType),
            },
          )
          .timeout(const Duration(seconds: 18));
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final result = HazardImageVerificationResult.fromJson(data);
        _log(
          'AI result: match=${result.matchesReportedHazard} '
          'category=${result.detectedCategory} '
          'confidence=${result.confidence} unavailable=${result.unavailable}',
        );
        return result;
      }
      if (data is Map) {
        final result = HazardImageVerificationResult.fromJson(
          data.cast<String, dynamic>(),
        );
        _log(
          'AI result: match=${result.matchesReportedHazard} '
          'category=${result.detectedCategory} '
          'confidence=${result.confidence} unavailable=${result.unavailable}',
        );
        return result;
      }
    } catch (error, stackTrace) {
      _log('AI image verification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const HazardImageVerificationResult(
        matchesReportedHazard: false,
        detectedCategory: 'uncertain',
        confidence: 0,
        reason: 'Image verification service is temporarily unavailable.',
        unavailable: true,
      );
    }

    _log('AI result: unexpected response');
    return const HazardImageVerificationResult(
      matchesReportedHazard: false,
      detectedCategory: 'uncertain',
      confidence: 0,
      reason: 'Image verification returned an unexpected response.',
      unavailable: true,
    );
  }

  void _log(String message) => debugPrint('[Verification] $message');
}

String hazardTypeVerificationValue(HazardType type) => switch (type) {
  HazardType.floodedRoad => 'flooded_road',
  HazardType.cloggedDrainage => 'clogged_drainage',
  HazardType.blockedWaterway => 'blocked_waterway',
  HazardType.overflowingCanal => 'overflowing_canal',
  HazardType.roadObstruction => 'road_obstruction',
  HazardType.damagedDrainage => 'damaged_drainage',
  HazardType.other => 'other',
};
