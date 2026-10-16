import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum WeatherDataFreshness { fresh, stale }

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureCelsius,
    required this.precipitationMm,
    required this.rainMm,
    required this.weatherCode,
    required this.observedAt,
  });

  final double temperatureCelsius;
  final double precipitationMm;
  final double rainMm;
  final int weatherCode;

  /// Model valid-time from Open-Meteo. This is not a rain-gauge observation.
  final String observedAt;
}

class WeatherForecastDay {
  const WeatherForecastDay({
    required this.date,
    required this.weatherCode,
    required this.maxTemperatureCelsius,
    required this.minTemperatureCelsius,
    required this.precipitationMm,
    this.precipitationProbabilityMax,
  });

  final String date;
  final int weatherCode;
  final double maxTemperatureCelsius;
  final double minTemperatureCelsius;
  final double precipitationMm;
  final int? precipitationProbabilityMax;
}

class WeatherForecastHour {
  const WeatherForecastHour({
    required this.time,
    required this.temperatureCelsius,
    required this.precipitationMm,
    required this.rainMm,
    required this.weatherCode,
    this.precipitationProbability,
  });

  final String time;
  final double temperatureCelsius;
  final double precipitationMm;
  final double rainMm;
  final int weatherCode;
  final int? precipitationProbability;
}

class WeatherForecastResponse {
  const WeatherForecastResponse({
    required this.current,
    required this.days,
    this.hours = const [],
    required this.endpoint,
    required this.jsonSample,
    required this.fetchedAt,
    this.freshness = WeatherDataFreshness.fresh,
    this.timezone = 'Asia/Manila',
    this.latitude,
    this.longitude,
  });

  final WeatherSnapshot current;
  final List<WeatherForecastDay> days;
  final List<WeatherForecastHour> hours;
  final Uri endpoint;
  final String jsonSample;
  final DateTime fetchedAt;
  final WeatherDataFreshness freshness;
  final String timezone;
  final double? latitude;
  final double? longitude;

  bool get isStale => freshness == WeatherDataFreshness.stale;
  String get sourceLabel => 'Open-Meteo model estimate';
}

class WeatherService {
  WeatherService({
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 12),
    Duration retryDelay = const Duration(milliseconds: 350),
  }) : _client = client ?? http.Client(),
       _requestTimeout = requestTimeout,
       _retryDelay = retryDelay;

  static const _freshFor = Duration(minutes: 10);
  static const _staleFallbackLimit = Duration(hours: 6);
  static final Map<String, _WeatherCacheEntry> _memoryCache = {};

  final http.Client _client;
  final Duration _requestTimeout;
  final Duration _retryDelay;

  Future<WeatherSnapshot> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async => (await getForecast(
    latitude: latitude,
    longitude: longitude,
    forecastDays: 1,
  )).current;

  Future<WeatherForecastResponse> getForecast({
    required double latitude,
    required double longitude,
    int forecastDays = 3,
    bool forceRefresh = false,
  }) async {
    _validateCoordinate(latitude, longitude);
    if (forecastDays < 1 || forecastDays > 16) {
      throw const WeatherException(
        'Forecast range must be between 1 and 16 days.',
      );
    }

    final uri = _forecastUri(latitude, longitude, forecastDays);
    final cacheKey = _cacheKey(latitude, longitude, forecastDays);
    final now = DateTime.now().toUtc();
    final memory = _memoryCache[cacheKey];
    if (!forceRefresh &&
        memory != null &&
        now.difference(memory.fetchedAt) <= _freshFor) {
      return _parseForecast(
        memory.payload,
        uri: uri,
        fetchedAt: memory.fetchedAt,
        freshness: WeatherDataFreshness.fresh,
      );
    }

    try {
      final payload = await _requestWithRetry(uri);
      final fetchedAt = DateTime.now().toUtc();
      final parsed = _parseForecast(
        payload,
        uri: uri,
        fetchedAt: fetchedAt,
        freshness: WeatherDataFreshness.fresh,
      );
      final entry = _WeatherCacheEntry(payload: payload, fetchedAt: fetchedAt);
      _memoryCache[cacheKey] = entry;
      await _writeCache(cacheKey, entry);
      return parsed;
    } catch (error) {
      final cached = memory ?? await _readCache(cacheKey);
      if (cached != null &&
          now.difference(cached.fetchedAt) <= _staleFallbackLimit) {
        return _parseForecast(
          cached.payload,
          uri: uri,
          fetchedAt: cached.fetchedAt,
          freshness: WeatherDataFreshness.stale,
        );
      }
      if (error is WeatherException) rethrow;
      throw const WeatherException(
        'Weather data is unavailable and no recent cached response exists.',
      );
    }
  }

  Uri _forecastUri(
    double latitude,
    double longitude,
    int forecastDays,
  ) => Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': latitude.toStringAsFixed(6),
    'longitude': longitude.toStringAsFixed(6),
    'current': 'temperature_2m,precipitation,rain,weather_code',
    'hourly':
        'temperature_2m,precipitation,precipitation_probability,rain,weather_code',
    'daily':
        'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max',
    'timezone': 'Asia/Manila',
    'timeformat': 'iso8601',
    'forecast_days': forecastDays.toString(),
  });

  Future<Map<String, dynamic>> _requestWithRetry(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(uri).timeout(_requestTimeout);
        if (response.statusCode != 200) {
          throw WeatherException(
            'Weather provider returned HTTP ${response.statusCode}.',
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const WeatherException(
            'Weather provider returned invalid JSON.',
          );
        }
        if (decoded['error'] == true) {
          throw WeatherException(
            decoded['reason']?.toString() ??
                'Weather provider rejected the request.',
          );
        }
        return decoded;
      } on TimeoutException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      } on FormatException catch (error) {
        lastError = error;
        break;
      } on WeatherException catch (error) {
        lastError = error;
        if (!error.message.contains('HTTP 5')) break;
      }
      if (attempt == 0) {
        await Future<void>.delayed(_retryDelay);
      }
    }
    if (lastError is WeatherException) throw lastError;
    throw const WeatherException('Weather request failed after retrying.');
  }

  WeatherForecastResponse _parseForecast(
    Map<String, dynamic> data, {
    required Uri uri,
    required DateTime fetchedAt,
    required WeatherDataFreshness freshness,
  }) {
    final current = _requiredMap(data, 'current');
    final daily = _requiredMap(data, 'daily');
    final hourly = _requiredMap(data, 'hourly');
    final currentTime = _requiredString(current, 'time');
    final currentValidTime = _parseProviderTime(currentTime);
    if (currentValidTime == null) {
      throw const WeatherException(
        'Weather response has an invalid current timestamp.',
      );
    }
    final nowUtc = DateTime.now().toUtc();
    if (currentValidTime.isAfter(nowUtc.add(const Duration(hours: 2)))) {
      throw const WeatherException(
        'Weather response timestamp is unexpectedly in the future.',
      );
    }
    if (nowUtc.difference(currentValidTime) > const Duration(hours: 2)) {
      throw const WeatherException(
        'Weather provider returned an outdated current estimate.',
      );
    }

    final days = _parseDays(daily);
    final hours = _parseHours(hourly);
    if (days.isEmpty || hours.isEmpty) {
      throw const WeatherException(
        'Weather response has no usable forecast values.',
      );
    }

    return WeatherForecastResponse(
      current: WeatherSnapshot(
        temperatureCelsius: _requiredDouble(current, 'temperature_2m'),
        precipitationMm: _requiredDouble(current, 'precipitation'),
        rainMm: _requiredDouble(current, 'rain'),
        weatherCode: _requiredInt(current, 'weather_code'),
        observedAt: currentTime,
      ),
      days: days,
      hours: hours,
      endpoint: uri,
      jsonSample: const JsonEncoder.withIndent('  ').convert({
        'current': current,
        'hourly': {
          'time': _list(hourly, 'time').take(6).toList(),
          'precipitation': _list(hourly, 'precipitation').take(6).toList(),
          'precipitation_probability': _list(
            hourly,
            'precipitation_probability',
          ).take(6).toList(),
          'rain': _list(hourly, 'rain').take(6).toList(),
          'weather_code': _list(hourly, 'weather_code').take(6).toList(),
        },
        'daily': daily,
      }),
      fetchedAt: fetchedAt,
      freshness: freshness,
      timezone: data['timezone']?.toString() ?? 'Asia/Manila',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
    );
  }

  List<WeatherForecastDay> _parseDays(Map<String, dynamic> daily) {
    final times = _list(daily, 'time');
    final codes = _list(daily, 'weather_code');
    final maxTemps = _list(daily, 'temperature_2m_max');
    final minTemps = _list(daily, 'temperature_2m_min');
    final precipitation = _list(daily, 'precipitation_sum');
    final probabilities = _list(daily, 'precipitation_probability_max');
    final count = [
      times.length,
      codes.length,
      maxTemps.length,
      minTemps.length,
      precipitation.length,
    ].reduce((a, b) => a < b ? a : b);
    final result = <WeatherForecastDay>[];
    for (var index = 0; index < count; index++) {
      final date = times[index]?.toString();
      final code = _asInt(codes[index]);
      final max = _asDouble(maxTemps[index]);
      final min = _asDouble(minTemps[index]);
      final rain = _asDouble(precipitation[index]);
      if (date == null ||
          DateTime.tryParse(date) == null ||
          code == null ||
          max == null ||
          min == null ||
          rain == null) {
        continue;
      }
      result.add(
        WeatherForecastDay(
          date: date,
          weatherCode: code,
          maxTemperatureCelsius: max,
          minTemperatureCelsius: min,
          precipitationMm: rain,
          precipitationProbabilityMax: index < probabilities.length
              ? _asInt(probabilities[index])
              : null,
        ),
      );
    }
    return result;
  }

  List<WeatherForecastHour> _parseHours(Map<String, dynamic> hourly) {
    final times = _list(hourly, 'time');
    final temperatures = _list(hourly, 'temperature_2m');
    final precipitation = _list(hourly, 'precipitation');
    final rain = _list(hourly, 'rain');
    final codes = _list(hourly, 'weather_code');
    final probabilities = _list(hourly, 'precipitation_probability');
    final count = [
      times.length,
      temperatures.length,
      precipitation.length,
      rain.length,
      codes.length,
    ].reduce((a, b) => a < b ? a : b);
    final now = DateTime.now().toUtc();
    final result = <WeatherForecastHour>[];
    for (var index = 0; index < count; index++) {
      final time = times[index]?.toString();
      final parsedTime = time == null ? null : _parseProviderTime(time);
      final temperature = _asDouble(temperatures[index]);
      final precipitationValue = _asDouble(precipitation[index]);
      final rainValue = _asDouble(rain[index]);
      final code = _asInt(codes[index]);
      if (parsedTime == null ||
          temperature == null ||
          precipitationValue == null ||
          rainValue == null ||
          code == null) {
        continue;
      }
      if (parsedTime.isBefore(now.subtract(const Duration(minutes: 30)))) {
        continue;
      }
      result.add(
        WeatherForecastHour(
          time: time!,
          temperatureCelsius: temperature,
          precipitationMm: precipitationValue,
          rainMm: rainValue,
          weatherCode: code,
          precipitationProbability: index < probabilities.length
              ? _asInt(probabilities[index])
              : null,
        ),
      );
      if (result.length == 6) break;
    }
    return result;
  }

  Map<String, dynamic> _requiredMap(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    throw WeatherException('Weather response is missing $key data.');
  }

  List<dynamic> _list(Map<String, dynamic> data, String key) =>
      data[key] is List ? data[key] as List<dynamic> : const [];

  double _requiredDouble(Map<String, dynamic> data, String key) {
    final value = _asDouble(data[key]);
    if (value == null) {
      throw WeatherException('Weather response is missing $key.');
    }
    return value;
  }

  int _requiredInt(Map<String, dynamic> data, String key) {
    final value = _asInt(data[key]);
    if (value == null) {
      throw WeatherException('Weather response is missing $key.');
    }
    return value;
  }

  String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      throw WeatherException('Weather response is missing $key.');
    }
    return value;
  }

  double? _asDouble(dynamic value) => value is num ? value.toDouble() : null;
  int? _asInt(dynamic value) => value is num ? value.toInt() : null;

  DateTime? _parseProviderTime(String value) {
    final hasOffset = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
    return DateTime.tryParse(hasOffset ? value : '$value+08:00')?.toUtc();
  }

  void _validateCoordinate(double latitude, double longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const WeatherException('Invalid weather location coordinates.');
    }
  }

  String _cacheKey(double latitude, double longitude, int days) =>
      'weather_v2_${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}_$days';

  Future<void> _writeCache(String key, _WeatherCacheEntry entry) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      key,
      jsonEncode({
        'fetched_at': entry.fetchedAt.toIso8601String(),
        'payload': entry.payload,
      }),
    );
  }

  Future<_WeatherCacheEntry?> _readCache(String key) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final fetchedAt = DateTime.tryParse(
        decoded['fetched_at']?.toString() ?? '',
      );
      final payload = decoded['payload'];
      if (fetchedAt == null || payload is! Map) return null;
      final entry = _WeatherCacheEntry(
        payload: payload.cast<String, dynamic>(),
        fetchedAt: fetchedAt.toUtc(),
      );
      _memoryCache[key] = entry;
      return entry;
    } catch (_) {
      return null;
    }
  }
}

class _WeatherCacheEntry {
  const _WeatherCacheEntry({required this.payload, required this.fetchedAt});

  final Map<String, dynamic> payload;
  final DateTime fetchedAt;
}

class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;

  @override
  String toString() => message;
}
