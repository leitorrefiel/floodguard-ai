import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/models/hazard_report.dart';
import 'package:floodguard/services/hazard_report_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('invalid coordinates are rejected before any remote request', () async {
    var requestCount = 0;
    final service = HazardReportService(
      client: _client((_) async {
        requestCount++;
        return http.Response('{}', 200);
      }),
      strictRemote: true,
    );

    await expectLater(
      service.createReport(
        type: HazardType.floodedRoad,
        severity: 'Moderate',
        location: 'Baliwag, Bulacan',
        description: 'Valid report description',
        latitude: 95,
        longitude: 120.89,
      ),
      throwsArgumentError,
    );
    expect(requestCount, 0);
  });

  test(
    'strict remote submission does not silently create a local report',
    () async {
      final service = HazardReportService(
        client: _client((_) async => throw http.ClientException('offline')),
        strictRemote: true,
      );

      await expectLater(
        service.createReport(
          type: HazardType.floodedRoad,
          severity: 'Moderate',
          location: 'Baliwag, Bulacan',
          description: 'Network failure validation',
          latitude: 14.95,
          longitude: 120.89,
        ),
        throwsA(isA<SupabaseRemoteRequiredException>()),
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('hazard_reports'), isNull);
    },
  );

  test('zero-row update fails in strict remote mode', () async {
    final service = HazardReportService(
      client: _client((request) async => _jsonResponse([], request)),
      strictRemote: true,
    );

    await expectLater(
      service.updateReport(_report()),
      throwsA(isA<SupabaseRemoteRequiredException>()),
    );
  });

  test('deleting a nonexistent report fails in strict remote mode', () async {
    final service = HazardReportService(
      client: _client((request) async => _jsonResponse([], request)),
      strictRemote: true,
    );

    await expectLater(
      service.deleteReport('00000000-0000-4000-8000-000000000001'),
      throwsA(isA<SupabaseRemoteRequiredException>()),
    );
  });

  test('successful report deletion requests remote photo cleanup', () async {
    var photoDeleteRequested = false;
    final service = HazardReportService(
      client: _client((request) async {
        if (request.url.path.contains('/rest/v1/hazard_reports')) {
          return _jsonResponse({
            'id': '00000000-0000-4000-8000-000000000001',
            'photo_path': 'user-a/report-a/photo.jpg',
          }, request);
        }
        if (request.url.path.contains(
          '/storage/v1/object/hazard-report-photos',
        )) {
          photoDeleteRequested = request.method == 'DELETE';
          return _jsonResponse([], request);
        }
        return _jsonResponse({}, request);
      }),
      strictRemote: true,
    );

    await service.deleteReport('00000000-0000-4000-8000-000000000001');

    expect(photoDeleteRequested, isTrue);
  });
}

SupabaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => SupabaseClient(
  'https://example.supabase.co',
  'test-publishable-key',
  httpClient: MockClient(handler),
);

http.Response _jsonResponse(Object body, http.BaseRequest request) =>
    http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );

HazardReport _report() {
  final now = DateTime.now();
  return HazardReport(
    id: '00000000-0000-4000-8000-000000000001',
    type: HazardType.floodedRoad,
    severity: 'Moderate',
    location: 'Baliwag, Bulacan',
    description: 'Update failure validation',
    latitude: 14.95,
    longitude: 120.89,
    userId: 'user-a',
    createdAt: now,
    updatedAt: now,
  );
}
