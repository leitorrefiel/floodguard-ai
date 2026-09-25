import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/services/weather_layer_service.dart';
import 'package:floodguard/services/weather_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('accepts provider-supplied zero rainfall as a dry estimate', () async {
    final service = WeatherService(
      client: MockClient(
        (_) async => http.Response(_weatherJson(rain: 0), 200),
      ),
    );

    final result = await service.getForecast(
      latitude: 14.9547,
      longitude: 120.8969,
    );

    expect(result.current.precipitationMm, 0);
    expect(result.current.rainMm, 0);
    expect(result.isStale, isFalse);
    expect(result.timezone, 'Asia/Manila');
  });

  test('does not convert missing current precipitation to zero', () async {
    final service = WeatherService(
      client: MockClient(
        (_) async => http.Response(
          _weatherJson(rain: 0, omitCurrentPrecipitation: true),
          200,
        ),
      ),
    );

    expect(
      () => service.getForecast(latitude: 14.9551, longitude: 120.8971),
      throwsA(isA<WeatherException>()),
    );
  });

  test('returns a clearly stale cache entry after a refresh failure', () async {
    var calls = 0;
    final service = WeatherService(
      client: MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response(_weatherJson(rain: 1.2), 200);
        throw http.ClientException('offline');
      }),
    );
    await service.getForecast(latitude: 14.9552, longitude: 120.8972);

    final cached = await service.getForecast(
      latitude: 14.9552,
      longitude: 120.8972,
      forceRefresh: true,
    );

    expect(cached.isStale, isTrue);
    expect(cached.current.precipitationMm, 1.2);
    expect(calls, 3);
  });

  test('rejects an outdated current estimate', () async {
    final oldTime = DateTime.now().toUtc().subtract(const Duration(hours: 4));
    final service = WeatherService(
      client: MockClient(
        (_) async => http.Response(_weatherJson(rain: 2, nowUtc: oldTime), 200),
      ),
    );

    expect(
      () => service.getForecast(latitude: 14.9553, longitude: 120.8973),
      throwsA(
        isA<WeatherException>().having(
          (error) => error.message,
          'message',
          contains('outdated'),
        ),
      ),
    );
  });

  test(
    'radar timeline reports unavailable coverage without inventing tiles',
    () async {
      final generated = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final service = WeatherLayerService(
        client: MockClient((request) async {
          if (request.url.toString() == WeatherLayerService.metadataUrl) {
            return http.Response(
              jsonEncode({
                'host': 'https://tilecache.rainviewer.com',
                'generated': generated,
                'radar': {
                  'past': [
                    {
                      'time': generated - 600,
                      'path': '/v2/radar/${generated - 600}',
                    },
                  ],
                },
              }),
              200,
            );
          }
          return http.Response.bytes(const [1, 2, 3], 200);
        }),
      );

      final timeline = await service.loadTimeline(
        latitude: 14.9547,
        longitude: 120.8969,
      );

      expect(timeline.frames, hasLength(1));
      expect(timeline.hasCoverage, isFalse);
    },
  );

  test('radar metadata older than the freshness window is stale', () {
    final timeline = RadarTimeline(
      host: 'https://tilecache.rainviewer.com',
      generatedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 36)),
      frames: const [],
      hasCoverage: true,
    );

    expect(timeline.isStale, isTrue);
  });
}

String _weatherJson({
  required double rain,
  bool omitCurrentPrecipitation = false,
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc()).add(const Duration(hours: 8));
  final currentTime = _minute(now);
  final nextHour = _minute(now.add(const Duration(hours: 1)));
  final current = <String, dynamic>{
    'time': currentTime,
    'temperature_2m': 28.4,
    'rain': rain,
    'weather_code': rain > 0 ? 61 : 1,
  };
  if (!omitCurrentPrecipitation) current['precipitation'] = rain;
  return jsonEncode({
    'latitude': 14.9547,
    'longitude': 120.8969,
    'timezone': 'Asia/Manila',
    'current': current,
    'hourly': {
      'time': [currentTime, nextHour],
      'temperature_2m': [28.4, 28.2],
      'precipitation': [rain, rain],
      'precipitation_probability': [20, 30],
      'rain': [rain, rain],
      'weather_code': [61, 61],
    },
    'daily': {
      'time': [currentTime.substring(0, 10)],
      'weather_code': [61],
      'temperature_2m_max': [30.0],
      'temperature_2m_min': [24.0],
      'precipitation_sum': [rain],
      'precipitation_probability_max': [30],
    },
  });
}

String _minute(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}T'
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
