import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureCelsius,
    required this.precipitationMm,
    required this.rainMm,
    required this.observedAt,
  });

  final double temperatureCelsius;
  final double precipitationMm;
  final double rainMm;
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

class WeatherForecastResponse {
  const WeatherForecastResponse({
    required this.current,
    required this.days,
    required this.endpoint,
    required this.jsonSample,
  });

  final WeatherSnapshot current;
  final List<WeatherForecastDay> days;
  final Uri endpoint;
  final String jsonSample;
}

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<WeatherSnapshot> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m,precipitation,rain',
      'timezone': 'auto',
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const WeatherException('Live weather is temporarily unavailable.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>?;
    if (current == null) {
      throw const WeatherException(
        'Live weather returned no current conditions.',
      );
    }

    return WeatherSnapshot(
      temperatureCelsius: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
      precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
      rainMm: (current['rain'] as num?)?.toDouble() ?? 0,
      observedAt: current['time'] as String? ?? '',
    );
  }

  Future<WeatherForecastResponse> getForecast({
    required double latitude,
    required double longitude,
    int forecastDays = 3,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m,precipitation,rain,weather_code',
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': forecastDays.toString(),
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const WeatherException('Forecast data is temporarily unavailable.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>?;
    final daily = data['daily'] as Map<String, dynamic>?;
    if (current == null || daily == null) {
      throw const WeatherException('Forecast returned incomplete data.');
    }

    final dates = (daily['time'] as List<dynamic>?) ?? const [];
    final weatherCodes = (daily['weather_code'] as List<dynamic>?) ?? const [];
    final maxTemps =
        (daily['temperature_2m_max'] as List<dynamic>?) ?? const [];
    final minTemps =
        (daily['temperature_2m_min'] as List<dynamic>?) ?? const [];
    final rainTotals =
        (daily['precipitation_sum'] as List<dynamic>?) ?? const [];
    final rainChances =
        (daily['precipitation_probability_max'] as List<dynamic>?) ?? const [];
    final dayCount = [
      dates.length,
      weatherCodes.length,
      maxTemps.length,
      minTemps.length,
      rainTotals.length,
    ].reduce((value, element) => value < element ? value : element);

    if (dayCount == 0) {
      throw const WeatherException('Forecast returned no daily results.');
    }

    return WeatherForecastResponse(
      current: WeatherSnapshot(
        temperatureCelsius:
            (current['temperature_2m'] as num?)?.toDouble() ?? 0,
        precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
        rainMm: (current['rain'] as num?)?.toDouble() ?? 0,
        observedAt: current['time'] as String? ?? '',
      ),
      days: List.generate(
        dayCount,
        (index) => WeatherForecastDay(
          date: dates[index] as String,
          weatherCode: (weatherCodes[index] as num?)?.toInt() ?? 0,
          maxTemperatureCelsius: (maxTemps[index] as num?)?.toDouble() ?? 0,
          minTemperatureCelsius: (minTemps[index] as num?)?.toDouble() ?? 0,
          precipitationMm: (rainTotals[index] as num?)?.toDouble() ?? 0,
          precipitationProbabilityMax: index < rainChances.length
              ? (rainChances[index] as num?)?.toInt()
              : null,
        ),
      ),
      endpoint: uri,
      jsonSample: const JsonEncoder.withIndent('  ').convert({
        'current': data['current'],
        'daily': {
          'time': dates,
          'weather_code': weatherCodes,
          'precipitation_sum': rainTotals,
          'precipitation_probability_max': rainChances,
        },
      }),
    );
  }
}

class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;
}
